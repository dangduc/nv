use std::io::{self, Read, Write};
use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use orgize::{Element, Event, Org};
use orgize::elements::Title;
use orgize::export::{DefaultHtmlHandler, HtmlEscape, HtmlHandler};

const INPUT_LIMIT: u64 = 16 * 1024 * 1024;
const OUTPUT_LIMIT: usize = 32 * 1024 * 1024;

#[derive(Default)]
struct HeadingLinks {
    anchors: Vec<String>,
    titles: HashMap<String, usize>,
    explicit_ids: HashMap<String, usize>,
}

fn primary_id<'a>(title: &'a Title<'_>) -> Option<&'a str> {
    ["CUSTOM_ID", "ID"].iter().find_map(|name| {
        title.properties.pairs.iter()
            .find(|(key, value)| key.eq_ignore_ascii_case(name) && !value.is_empty()
                  && !value.chars().any(|c| c.is_whitespace() || c.is_control()))
            .map(|(_, value)| value.as_ref())
    })
}

fn fragment(id: &str) -> String {
    const HEX: &[u8] = b"0123456789ABCDEF";
    let mut result = String::from("#");
    for byte in id.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            result.push(byte as char);
        } else {
            result.push('%');
            result.push(HEX[(byte >> 4) as usize] as char);
            result.push(HEX[(byte & 15) as usize] as char);
        }
    }
    result
}

fn has_scheme(path: &str) -> bool {
    path.split_once(':').is_some_and(|(scheme, _)| {
        scheme.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
            && scheme.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'-' | b'.'))
    })
}

impl HeadingLinks {
    fn new(org: &Org<'_>) -> Self {
        let headings: Vec<_> = org.iter().filter_map(|event| match event {
            Event::Start(Element::Title(title)) => Some(title),
            _ => None,
        }).collect();
        // Reserve all explicit IDs first, including IDs on later headings.
        let reserved: HashSet<_> = headings.iter().filter_map(|title| primary_id(title)).collect();
        let mut used = HashSet::new();
        let mut result = Self { anchors: Vec::new(), titles: HashMap::new(), explicit_ids: HashMap::new() };
        for (index, title) in headings.iter().enumerate() {
            let anchor = match primary_id(title) {
                Some(id) if used.insert(id.to_string()) => id.to_string(),
                _ => {
                    let base = format!("nv-org-heading-{}", index + 1);
                    let mut candidate = base.clone();
                    let mut suffix = 2;
                    while reserved.contains(candidate.as_str()) || used.contains(&candidate) {
                        candidate = format!("{base}-{suffix}");
                        suffix += 1;
                    }
                    used.insert(candidate.clone());
                    candidate
                }
            };
            result.anchors.push(anchor);
            if !title.raw.is_empty() {
                result.titles.entry(title.raw.to_string()).or_insert(index);
            }
            // Ambiguous titles and IDs consistently select the first heading.
            for (key, value) in &title.properties.pairs {
                if (key.eq_ignore_ascii_case("CUSTOM_ID") || key.eq_ignore_ascii_case("ID")) && !value.is_empty() {
                    result.explicit_ids.entry(value.to_string()).or_insert(index);
                }
            }
        }
        result
    }

    fn href<'a>(&self, path: &'a str) -> Cow<'a, str> {
        if let Some(file) = path.strip_prefix("file:") { return Cow::Borrowed(file); }
        let heading = if let Some(title) = path.strip_prefix('*') {
            self.titles.get(title.trim())
        } else if let Some(id) = path.strip_prefix('#') {
            self.explicit_ids.get(id)
        } else if has_scheme(path) || ["/", "./", "../", "~/"].iter().any(|prefix| path.starts_with(prefix)) {
            None
        } else {
            self.titles.get(path)
        };
        match heading {
            Some(index) => Cow::Owned(fragment(&self.anchors[*index])),
            None => Cow::Borrowed(path),
        }
    }
}

#[derive(Default)]
struct PreviewHtml {
    default: DefaultHtmlHandler,
    lists: Vec<bool>,
    headings: HeadingLinks,
    next_heading: usize,
}

// Org escapes lines that could open a heading or another block with one comma.
fn block_text(contents: &str) -> String {
    let mut out = String::with_capacity(contents.len());
    for line in contents.split_inclusive('\n') {
        if line.starts_with(',') {
            let tail = line.trim_start_matches(',');
            if tail.starts_with('*') || tail.starts_with("#+") {
                out.push_str(&line[1..]);
                continue;
            }
        }
        out.push_str(line);
    }
    out
}

impl HtmlHandler<io::Error> for PreviewHtml {
    fn start<W: Write>(&mut self, mut w: W, element: &Element) -> io::Result<()> {
        match element {
            Element::List(list) => {
                self.lists.push(list.ordered);
                write!(w, "<{}>", if list.ordered { "ol" } else { "ul" })
            }
            Element::ListItem(item) => {
                if let Some(ordered) = self.lists.last_mut() {
                    if *ordered != item.ordered {
                        write!(w, "</{}><{}>", if *ordered { "ol" } else { "ul" }, if item.ordered { "ol" } else { "ul" })?;
                        *ordered = item.ordered;
                    }
                }
                write!(w, "<li>")
            }
            Element::Title(title) => {
                let anchor = self.headings.anchors.get(self.next_heading)
                    .ok_or_else(|| io::Error::other("heading index does not match document"))?;
                self.next_heading += 1;
                write!(w, "<h{} id=\"{}\">", title.level.min(6), HtmlEscape(anchor))?;
                if let Some(keyword) = &title.keyword {
                    write!(w, "<span class=\"org-todo\">{}</span> ", HtmlEscape(keyword))?;
                }
                if let Some(priority) = title.priority {
                    write!(w, "[#{}] ", HtmlEscape(priority.to_string()))?;
                }
                Ok(())
            }
            Element::SourceBlock(block) => write!(w, "<pre><code>{}</code></pre>", HtmlEscape(block_text(&block.contents))),
            Element::ExampleBlock(block) => write!(w, "<pre>{}</pre>", HtmlEscape(block_text(&block.contents))),
            Element::Link(link) => {
                let path = link.path.strip_prefix("file:").unwrap_or(&link.path);
                write!(w, "<a href=\"{}\">{}</a>", HtmlEscape(self.headings.href(&link.path)), HtmlEscape(link.desc.as_deref().unwrap_or(path)))
            }
            Element::Keyword(keyword) if keyword.key.eq_ignore_ascii_case("INCLUDE") || keyword.key.eq_ignore_ascii_case("SETUPFILE") => {
                write!(w, "<pre>#+{}: {}</pre>", HtmlEscape(&keyword.key), HtmlEscape(&keyword.value))
            }
            _ => self.default.start(w, element),
        }
    }
    fn end<W: Write>(&mut self, mut w: W, element: &Element) -> io::Result<()> {
        if let Element::List(_) = element {
            let ordered = self.lists.pop().unwrap_or(false);
            return write!(w, "</{}>", if ordered { "ol" } else { "ul" });
        }
        if let Element::Title(title) = element {
            if !title.tags.is_empty() {
                write!(w, " <span class=\"org-tags\">:")?;
                for tag in &title.tags {
                    write!(w, "{}:", HtmlEscape(tag))?;
                }
                write!(w, "</span>")?;
            }
        }
        self.default.end(w, element)
    }
}

struct LimitedOutput(Vec<u8>);
impl Write for LimitedOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > OUTPUT_LIMIT.saturating_sub(self.0.len()) {
            return Err(io::Error::other("generated HTML exceeds 32 MB"));
        }
        self.0.write(bytes)
    }
    fn flush(&mut self) -> io::Result<()> { Ok(()) }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut source = String::new();
    io::stdin().take(INPUT_LIMIT + 1).read_to_string(&mut source)?;
    if source.len() as u64 > INPUT_LIMIT { return Err("source exceeds 16 MB".into()); }
    let mut output = LimitedOutput(Vec::new());
    let org = Org::parse(&source);
    let mut handler = PreviewHtml { default: DefaultHtmlHandler, lists: Vec::new(), headings: HeadingLinks::new(&org), next_heading: 0 };
    org.write_html_custom(&mut output, &mut handler)?;
    io::stdout().lock().write_all(&output.0)?;
    Ok(())
}
