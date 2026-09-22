#pragma once
#include "unicode_identifiers.hpp"
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <locale>
#include <map>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
namespace papng {
struct Json {
    enum Type { Null, Number, String, Bool, Array, Object } type = Null;
    double number = 0;
    std::string text;
    std::vector<Json> array;
    std::map<std::string, Json> object;
    const Json &operator[](const std::string &k) const {
        static const Json nil;
        auto it = object.find(k);
        return it == object.end() ? nil : it->second;
    }
    bool finite() const { return type == Number && std::isfinite(number); }
    bool uint() const { return finite() && number >= 0 && number <= 4294967295.0 && floor(number) == number; }
    bool has(const std::string &k) const { return object.count(k) != 0; }
};
class Json5 {
    const std::string &s;
    size_t p = 0;
    [[noreturn]] void fail() const { throw std::runtime_error("Invalid JSON5 at byte " + std::to_string(p)); }
    char peek() const { return p < s.size() ? s[p] : 0; }
    static void utf8(std::string &out, uint32_t c) {
        if (c < 128)
            out += char(c);
        else if (c < 2048) {
            out += char(192 | (c >> 6));
            out += char(128 | (c & 63));
        } else if (c < 65536) {
            out += char(224 | (c >> 12));
            out += char(128 | ((c >> 6) & 63));
            out += char(128 | (c & 63));
        } else {
            out += char(240 | (c >> 18));
            out += char(128 | ((c >> 12) & 63));
            out += char(128 | ((c >> 6) & 63));
            out += char(128 | (c & 63));
        }
    }
    uint32_t code(size_t &at) const {
        if (at >= s.size())
            return 0;
        uint32_t c = (unsigned char)s[at++];
        if (c < 128)
            return c;
        int n = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc2 ? 1 : -1;
        if (n < 0 || c > 0xf4)
            fail();
        uint32_t v = c & ((1 << (6 - n)) - 1);
        for (int i = 0; i < n; i++) {
            if (at >= s.size() || ((unsigned char)s[at] & 192) != 128)
                fail();
            v = (v << 6) | ((unsigned char)s[at++] & 63);
        }
        if (v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff) || v < (n == 1 ? 128 : n == 2 ? 2048 : 65536))
            fail();
        return v;
    }
    static bool white(uint32_t c) {
        return c == 9 || c == 10 || c == 11 || c == 12 || c == 13 || c == 32 || c == 160 || c == 0x1680 ||
               (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f ||
               c == 0x3000 || c == 0xfeff;
    }
    void space() {
        while (p < s.size()) {
            size_t q = p;
            auto c = code(q);
            if (white(c)) {
                p = q;
                continue;
            }
            if (s.compare(p, 2, "//") == 0) {
                p += 2;
                while (p < s.size()) {
                    q = p;
                    c = code(q);
                    if (c == 10 || c == 13 || c == 0x2028 || c == 0x2029)
                        break;
                    p = q;
                }
                continue;
            }
            if (s.compare(p, 2, "/*") == 0) {
                auto end = s.find("*/", p + 2);
                if (end == std::string::npos)
                    fail();
                p = end + 2;
                continue;
            }
            break;
        }
    }
    uint32_t hex(int n) {
        uint32_t v = 0;
        for (int i = 0; i < n; i++) {
            char c = peek();
            p++;
            int x = c >= '0' && c <= '9'   ? c - '0'
                    : c >= 'a' && c <= 'f' ? c - 'a' + 10
                    : c >= 'A' && c <= 'F' ? c - 'A' + 10
                                           : -1;
            if (x < 0)
                fail();
            v = (v << 4) | x;
        }
        return v;
    }
    std::string quoted() {
        char quote = s[p++];
        std::string o;
        while (p < s.size()) {
            size_t begin = p;
            uint32_t c = code(p);
            if (c == (uint32_t)quote)
                return o;
            if (c == 10 || c == 13)
                fail();
            if (c != '\\') {
                o.append(s, begin, p - begin);
                continue;
            }
            c = code(p);
            if (c == 10 || c == 13 || c == 0x2028 || c == 0x2029) {
                if (c == 13 && peek() == 10)
                    p++;
                continue;
            }
            if (c == 'u' || c == 'x') {
                auto h = hex(c == 'u' ? 4 : 2);
                if (h >= 0xd800 && h <= 0xdbff) {
                    if (s.compare(p, 2, "\\u"))
                        fail();
                    p += 2;
                    auto l = hex(4);
                    if (l < 0xdc00 || l > 0xdfff)
                        fail();
                    h = 0x10000 + ((h - 0xd800) << 10) + l - 0xdc00;
                } else if (h >= 0xdc00 && h <= 0xdfff)
                    fail();
                utf8(o, h);
                continue;
            }
            if (c == '0') {
                if (peek() >= '0' && peek() <= '9')
                    fail();
                o += char(0);
                continue;
            }
            if (!c || (c >= '1' && c <= '9'))
                fail();
            switch (c) {
            case 'b':
                o += '\b';
                break;
            case 'f':
                o += '\f';
                break;
            case 'n':
                o += '\n';
                break;
            case 'r':
                o += '\r';
                break;
            case 't':
                o += '\t';
                break;
            case 'v':
                o += '\v';
                break;
            default:
                utf8(o, c);
            }
        }
        fail();
    }
    std::string bare(bool key) {
        std::string o;
        while (p < s.size()) {
            size_t q = p;
            auto c = code(q);
            if (white(c) || (c < 128 && std::string("{}[]:,/\"'").find(char(c)) != std::string::npos))
                break;
            if (c == '\\') {
                if (!key || s.compare(p, 2, "\\u"))
                    fail();
                p += 2;
                c = hex(4);
                utf8(o, c);
            } else {
                o.append(s, p, q - p);
                p = q;
            }
        }
        return o;
    }
    Json value(int depth) {
        if (depth > 128)
            fail();
        space();
        Json v;
        char c = peek();
        if (c == '\'' || c == '"') {
            v.type = Json::String;
            v.text = quoted();
            return v;
        }
        if (c == '{' || c == '[') {
            bool obj = c == '{';
            v.type = obj ? Json::Object : Json::Array;
            char end = obj ? '}' : ']';
            p++;
            space();
            while (peek() != end) {
                if (!peek())
                    fail();
                if (obj) {
                    std::string k;
                    bool quotedKey = peek() == '\'' || peek() == '"';
                    if (quotedKey)
                        k = quoted();
                    else {
                        k = bare(true);
                        if (k.empty())
                            fail();
                        Json5 keyParser(k);
                        size_t at = 0;
                        bool first = true;
                        while (at < k.size()) {
                            auto codepoint = keyParser.code(at);
                            if (codepoint != '_' && codepoint != '$' &&
                                !(first ? identifierCode(codepoint, IdStart) : identifierCode(codepoint, IdContinue)))
                                fail();
                            first = false;
                        }
                    }
                    space();
                    if (peek() != ':' || v.object.count(k))
                        fail();
                    p++;
                    v.object.emplace(k, value(depth + 1));
                } else
                    v.array.push_back(value(depth + 1));
                space();
                if (peek() != ',')
                    break;
                p++;
                space();
            }
            if (peek() != end)
                fail();
            p++;
            return v;
        }
        auto raw = bare(false);
        if (raw == "null")
            return v;
        if (raw == "true" || raw == "false") {
            v.type = Json::Bool;
            v.number = raw == "true";
            return v;
        }
        static const std::regex number("[+-]?(0[xX][0-9a-fA-F]+|((0|[1-9][0-9]*)(\\.[0-9]*)?|\\.[0-9]+)([eE]["
                                       "+-]?[0-9]+)?|Infinity|NaN)");
        if (!std::regex_match(raw, number))
            fail();
        v.type = Json::Number;
        if (raw.find("0x") != std::string::npos || raw.find("0X") != std::string::npos ||
            raw.find("Infinity") != std::string::npos || raw.find("NaN") != std::string::npos)
            v.number = strtod(raw.c_str(), nullptr);
        else {
            std::istringstream stream(raw);
            stream.imbue(std::locale::classic());
            stream >> v.number;
            if (stream.fail())
                v.number = raw[0] == '-' ? -std::numeric_limits<double>::infinity()
                                         : std::numeric_limits<double>::infinity();
        }
        return v;
    }

  public:
    explicit Json5(const std::string &input) : s(input) {}
    Json parse() {
        if (s.compare(0, 3, "\xef\xbb\xbf") == 0)
            fail();
        size_t q = 0;
        while (q < s.size())
            code(q);
        Json v = value(0);
        space();
        if (p != s.size())
            fail();
        return v;
    }
};
} // namespace papng
