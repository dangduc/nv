use std::io::{self, Read, Write};
use orgize::{Element, Org};
use orgize::export::{DefaultHtmlHandler, HtmlEscape, HtmlHandler};

const INPUT_LIMIT: u64 = 16 * 1024 * 1024;
const OUTPUT_LIMIT: usize = 32 * 1024 * 1024;

#[derive(Default)]
struct PreviewHtml(DefaultHtmlHandler, Vec<bool>);

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
                self.1.push(list.ordered);
                write!(w, "<{}>", if list.ordered { "ol" } else { "ul" })
            }
            Element::ListItem(item) => {
                if let Some(ordered) = self.1.last_mut() {
                    if *ordered != item.ordered {
                        write!(w, "</{}><{}>", if *ordered { "ol" } else { "ul" }, if item.ordered { "ol" } else { "ul" })?;
                        *ordered = item.ordered;
                    }
                }
                write!(w, "<li>")
            }
            Element::Title(title) => {
                write!(w, "<h{}", title.level.min(6))?;
                if let Some(id) = title.properties.pairs.iter().find(|(key, _)| key == "CUSTOM_ID").or_else(|| title.properties.pairs.iter().find(|(key, _)| key == "ID")).map(|(_, value)| value) {
                    write!(w, " id=\"{}\"", HtmlEscape(id))?;
                }
                write!(w, ">")?;
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
                write!(w, "<a href=\"{}\">{}</a>", HtmlEscape(path), HtmlEscape(link.desc.as_deref().unwrap_or(path)))
            }
            Element::Keyword(keyword) if keyword.key.eq_ignore_ascii_case("INCLUDE") || keyword.key.eq_ignore_ascii_case("SETUPFILE") => {
                write!(w, "<pre>#+{}: {}</pre>", HtmlEscape(&keyword.key), HtmlEscape(&keyword.value))
            }
            _ => self.0.start(w, element),
        }
    }
    fn end<W: Write>(&mut self, mut w: W, element: &Element) -> io::Result<()> {
        if let Element::List(_) = element {
            let ordered = self.1.pop().unwrap_or(false);
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
        self.0.end(w, element)
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
    Org::parse(&source).write_html_custom(&mut output, &mut PreviewHtml::default())?;
    io::stdout().lock().write_all(&output.0)?;
    Ok(())
}
