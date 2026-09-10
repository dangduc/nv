#import <Foundation/Foundation.h>
#include <tree_sitter/api.h>
extern const TSLanguage *tree_sitter_org(void);
static void Dump(TSNode node, NSString *source, int depth) {
    NSRange range = NSMakeRange(ts_node_start_byte(node) / 2, (ts_node_end_byte(node) - ts_node_start_byte(node)) / 2);
    NSString *value = [[source substringWithRange:range] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    value = [value stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    printf("%*s%s %s [%s]\n", depth * 2, "", ts_node_type(node), [NSStringFromRange(range) UTF8String], [value UTF8String]);
    for (uint32_t index = 0; index < ts_node_child_count(node); index++) Dump(ts_node_child(node, index), source, depth + 1);
}
int main(void) { @autoreleasepool {
    for (NSString *source in @[@"Review *first\nsecond* today.\n", @"Review *first\r\nsecond* today.\r\n"]) {
        TSParser *parser = ts_parser_new();
        if (!ts_parser_set_language(parser, tree_sitter_org())) return 1;
        NSData *data = [source dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
        TSTree *tree = ts_parser_parse_string_encoding(parser, NULL, [data bytes], (uint32_t)[data length], TSInputEncodingUTF16LE);
        if (!tree) return 2;
        Dump(ts_tree_root_node(tree), source, 0);
        ts_tree_delete(tree); ts_parser_delete(parser);
    }
    return 0;
}}
