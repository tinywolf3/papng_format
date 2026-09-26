#define PAPNG_BUILD
#include "papng.h"
#include "json5.hpp"
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_MAX_DIMENSIONS 33554432
#include "third_party/stb_image.h"
#define MINIZ_USE_UNALIGNED_LOADS_AND_STORES 0
#define MINIZ_LITTLE_ENDIAN 1
#define MINIZ_HAS_64BIT_REGISTERS 1
#define MINIZ_UNALIGNED_USE_MEMCPY 1
#include "third_party/miniz_tinfl.inc"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <limits>
#include <memory>
#include <random>
namespace papng {
using Bytes = std::vector<unsigned char>;
constexpr size_t Limit = 128u * 1024 * 1024, CacheLimit = 32u * 1024 * 1024;
// UI labels have a separate budget; the full metadata remains available verbatim.
std::string label(const std::string& text, size_t maximum=256) {
    size_t n=std::min(text.size(),maximum);
    while(n<text.size() && n>0 && (static_cast<unsigned char>(text[n])&0xc0)==0x80) --n;
    return text.substr(0,n)+(n<text.size()?"…":"");
}
struct Reader {
    const Bytes &b;
    size_t p = 0;
    void need(size_t n) {
        if (p > b.size() || n > b.size() - p)
            throw std::runtime_error("Truncated chunk");
    }
    uint32_t u(int n) {
        need(n);
        uint32_t v = 0;
        while (n--)
            v = (v << 8) | b[p++];
        return v;
    }
    int64_t s(int n) {
        auto v = u(n);
        return v & (1u << (n * 8 - 1)) ? int64_t(v) - (int64_t(1) << (n * 8)) : v;
    }
    Bytes take(size_t n) {
        need(n);
        Bytes v(b.begin() + p, b.begin() + p + n);
        p += n;
        return v;
    }
};
uint32_t crc(const unsigned char *b, size_t n) {
    uint32_t c = ~0u;
    for (size_t i = 0; i < n; i++) {
        c ^= b[i];
        for (int k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xedb88320u & uint32_t(-int(c & 1)));
    }
    return ~c;
}
void be(Bytes &b, uint32_t n, int count) {
    for (int i = count - 1; i >= 0; i--)
        b.push_back((n >> (i * 8)) & 255);
}
void chunk(Bytes &out, const char *name, const Bytes &b) {
    be(out, uint32_t(b.size()), 4);
    size_t start = out.size();
    out.insert(out.end(), name, name + 4);
    out.insert(out.end(), b.begin(), b.end());
    be(out, crc(out.data() + start, b.size() + 4), 4);
}
Bytes inflate(const Bytes &b, size_t limit) {
    Bytes out(std::max(size_t(1), limit));
    size_t input = b.size(), output = limit;
    tinfl_decompressor state;
    tinfl_init(&state);
    auto status = tinfl_decompress(&state, b.data(), &input, out.data(), out.data(), &output,
                                   TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    if (status != TINFL_STATUS_DONE || input != b.size())
        throw std::runtime_error("Invalid, trailing or oversized zlib stream");
    out.resize(output);
    return out;
}
struct Frame {
    uint32_t w = 0, h = 0, x = 0, y = 0, num = 1, den = 100;
    int dispose = 0, blend = 0;
    bool idat = false;
    Bytes data;
};
struct Distribution {
    int kind = 0;
    bool valid = true;
    std::vector<std::pair<int64_t, uint32_t>> items;
};
struct Control {
    uint32_t kind = ~0u;
    bool valid = false;
    std::vector<int64_t> v;
};
struct Map {
    uint32_t w, h;
    Bytes packed;
};
struct Clip {
    std::string name, id;
    uint32_t start, end, plays;
};
struct Pose {
    double x, y, r;
};
struct State {
    int frame = -1;
    Bytes pixels, marks, previous, previousMarks;
    size_t size() const { return pixels.size() + marks.size() + previous.size() + previousMarks.size(); }
};
struct Cached {
    State state;
    uint64_t stamp;
};
class Player {
  public:
    uint32_t width = 0, height = 0, plays = 0;
    int source = 0, maskCount = 0, visible = -1, revision = 0, selected = -1, clip = -1;
    std::string error, warnings, metadata, nameBuffer;
    std::vector<Frame> frames;
    Bytes header, colors;
    std::vector<Distribution> distributions{Distribution()};
    std::map<int, std::vector<Control>> controls;
    std::vector<Map> maps;
    std::map<int, int> bindings;
    std::map<int, Bytes> rawCache, maskCache;
    std::map<int, std::array<double, 4>> hints;
    std::vector<Clip> clips;
    std::vector<std::string> maskNames, socketNames;
    std::map<int, std::vector<Pose>> poses;
    std::vector<double> offsets, saturationOffsets, valueOffsets;
    std::vector<std::array<double, 4>> sums;
    State state;
    std::map<int, Cached> cache;
    std::map<int, int> priority;
    uint64_t stamp = 0;
    size_t cacheBytes = 0, rawBytes = 0, maskBytes = 0;
    Bytes presented, presentedMarks;
    int start = 0, end = 0, current = -1;
    uint32_t repeat = 0;
    uint64_t completed = 0;
    bool ended = false;
    double remaining = 0;
    Control visit;
    std::mt19937_64 rng{std::random_device{}()};
    void warn(const std::string &s) {
        if (warnings.size() < 16000 && warnings.find(s) == std::string::npos)
            warnings += s + "\n";
    }
    static void require(bool condition, const char *s) {
        if (!condition)
            throw std::runtime_error(s);
    }
    explicit Player(const Bytes &bytes) {
        load(bytes);
        offsets.resize(maskCount); saturationOffsets.resize(maskCount); valueOffsets.resize(maskCount);
        maskNames.resize(maskCount);
        sums.resize(maskCount);
        end = int(frames.size()) - 1;
        repeat = plays;
        priority[0] = 3;
        for (const auto &pair : controls)
            for (const auto &c : pair.second)
                if (valid(c, pair.first) && (c.kind == 2 || c.kind == 3))
                    priority[int(c.v[0] + (c.kind == 2 ? pair.first : 0))] = 6;
        for (auto &c : clips)
            priority[c.start] = 5;
        means();
        restart(-1);
    }
    Player() = default;
    void load(const Bytes &bytes) {
        static const unsigned char sig[] = {137, 80, 78, 71, 13, 10, 26, 10};
        require(bytes.size() >= 8 && bytes.size() <= Limit && !memcmp(bytes.data(), sig, 8),
                "Not a PNG file or file exceeds 128 MiB");
        Reader r{bytes, 8};
        uint32_t count = 0, sequence = 0;
        bool idat = false, afterIdat = false, endedFile = false;
        Bytes first;
        std::vector<std::pair<Bytes, bool>> ex, md;
        std::vector<Bytes> texts;
        while (r.p < bytes.size()) {
            uint32_t n = r.u(4);
            size_t chunkAt = r.p;
            auto nb = r.take(4);
            std::string name(nb.begin(), nb.end());
            auto b = r.take(n);
            auto checksum = r.u(4);
            bool good = crc(bytes.data() + chunkAt, n + 4) == checksum;
            for (auto c : nb)
                require((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'), "Invalid chunk name");
            require(nb[2] >= 'A' && nb[2] <= 'Z', "Invalid reserved chunk bit");
            require(width || name == "IHDR", "IHDR must be first");
            require(good || name == "paEX" || name == "paMD" || name == "iTXt", "PNG CRC mismatch");
            if (idat && name != "IDAT")
                afterIdat = true;
            Reader q{b};
            if (name == "IHDR") {
                require(!width && n == 13, "Invalid IHDR");
                width = q.u(4);
                height = q.u(4);
                header = b;
                require(width && height && uint64_t(width) * height <= Limit / 4, "Canvas exceeds 128 MiB");
            } else if (name == "acTL") {
                require(!count && !idat && n == 8, "Invalid acTL");
                count = q.u(4);
                plays = q.u(4);
                require(count > 0, "Empty animation");
            } else if (name == "fcTL") {
                require(count && n == 26 && q.u(4) == sequence++, "Invalid frame sequence");
                require(frames.empty() || !frames.back().data.empty(), "Missing frame data");
                Frame f;
                f.w = q.u(4);
                f.h = q.u(4);
                f.x = q.u(4);
                f.y = q.u(4);
                f.num = q.u(2);
                f.den = q.u(2);
                f.dispose = q.u(1);
                f.blend = q.u(1);
                f.idat = !idat;
                require(f.w && f.h && uint64_t(f.x) + f.w <= width && uint64_t(f.y) + f.h <= height &&
                            f.dispose <= 2 && f.blend <= 1,
                        "Invalid frame bounds or blend");
                if (!idat)
                    require(frames.empty() && f.w == width && f.h == height && !f.x && !f.y,
                            "Invalid default frame");
                frames.push_back(std::move(f));
            } else if (name == "IDAT") {
                require(!afterIdat, "Nonconsecutive IDAT");
                idat = true;
                auto &dest = frames.empty() ? first : frames.back().data;
                dest.insert(dest.end(), b.begin(), b.end());
            } else if (name == "fdAT") {
                require(idat && !frames.empty() && !frames.back().idat && n >= 4 && q.u(4) == sequence++,
                        "Invalid fdAT");
                frames.back().data.insert(frames.back().data.end(), b.begin() + 4, b.end());
            } else if (name == "paEX")
                ex.push_back({b, good && !idat});
            else if (name == "paMD")
                md.push_back({b, good && !idat && ex.size() == 1});
            else if (name == "iTXt") {
                if (good)
                    texts.push_back(b);
                else
                    warn("iTXt CRC error; metadata ignored");
            } else if (name == "PLTE" || name == "tRNS")
                chunk(colors, name.c_str(), b);
            else if (name == "IEND") {
                require(!n && idat && r.p == bytes.size(), "Invalid IEND");
                endedFile = true;
                break;
            } else
                require(nb[0] >= 'a', "Unknown critical PNG chunk");
        }
        require(endedFile && frames.size() == count && (!count || !frames.back().data.empty()),
                "Missing end or wrong frame count");
        source = count ? 1 : 0;
        if (ex.empty()) {
            if (!count) {
                Frame f;
                f.w = width;
                f.h = height;
                f.data = std::move(first);
                frames.push_back(std::move(f));
                plays = 1;
            }
            for (auto &f : frames) {
                if (!f.num) {
                    f.num = 1;
                    f.den = 100;
                    warn("Imported zero delay normalized to 10 ms");
                } else if (!f.den)
                    f.den = 100;
            }
        } else {
            source = 2;
            auto it = std::find_if(ex.begin(), ex.end(), [](const auto &e) {
                return e.first.size() >= 8 && !memcmp(e.first.data(), "PAPNG\0\0\0", 8);
            });
            require(it != ex.end(), "Unknown PAPNG identifier");
            Reader v{it->first, 8};
            require(v.u(2) == 1, "Unsupported PAPNG major version");
            require(count && header[8] == 8 && header[9] == 6, "PAPNG requires RGBA8 animation");
            bool usable = false;
            if (ex.size() == 1 && it->second) {
                try {
                    usable = extension(it->first);
                } catch (const std::exception &) {
                    warn("Truncated paEX: validated prefix retained");
                    usable = it->first.size() >= 56;
                }
            } else
                warn("paEX CRC, location or duplicate error: extension ignored");
            if (md.size() > 1 || (!md.empty() && !md[0].second))
                warn("Invalid paMD: masks ignored");
            else if (usable && !md.empty()) {
                try {
                    masks(md[0].first);
                } catch (const std::exception &) {
                    warn("Truncated paMD: validated prefix retained");
                }
            }
            metadataParse(texts);
        }
    }
    bool extension(const Bytes &b) {
        Reader r{b, 10};
        auto minor = r.u(2);
        auto size = r.u(4);
        if (b.size() < 56 || size < 56 || size > b.size() || (minor <= 1 && size != 56)) {
            warn("Invalid paEX header");
            return false;
        }
        auto flags = r.u(4);
        double dw = r.u(4), dh = r.u(4), bx = r.s(4), by = r.s(4), bw = r.u(4), bh = r.u(4), scale = r.u(4),
               px = r.s(4), py = r.s(4);
        if (flags & 1 && dw > 0 && dh > 0)
            hints[0] = {dw, dh, 0, 0};
        if (flags & 2 && bx >= 0 && by >= 0 && bw > 0 && bh > 0 && bx + bw <= width && by + bh <= height)
            hints[1] = {bx, by, bw, bh};
        if (flags & 4 && scale > 0)
            hints[2] = {scale, 0, 0, 0};
        if (flags & 8)
            hints[3] = {px, py, 0, 0};
        if (minor > 1 || flags >> 4)
            warn("Unknown extension fields ignored");
        r.p = size;
        auto masks = r.u(2);
        if (masks <= 32768)
            maskCount = masks;
        else
            warn("Invalid mask count");
        auto n = r.u(1);
        for (uint32_t i = 0; i < n; i++) {
            Distribution d;
            d.kind = r.u(1);
            auto len = r.u(3);
            auto p = r.take(len);
            Reader q{p};
            d.valid = d.kind <= 3 && !len;
            if (d.kind == 4 && len >= 4) {
                auto count = q.u(4);
                if (count && uint64_t(count) * 4 + 4 == len) {
                    uint64_t total = 0;
                    for (uint32_t j = 0; j < count; j++) {
                        auto value = q.s(3);
                        auto weight = q.u(1);
                        d.items.push_back({value, weight});
                        total += weight;
                    }
                    d.valid = total > 0;
                }
            }
            distributions.push_back(std::move(d));
            if (!distributions.back().valid)
                warn("Invalid distribution");
        }
        n = r.u(4);
        for (uint32_t i = 0; i < n; i++) {
            auto frame = r.u(4);
            Control c;
            c.kind = r.u(4);
            auto len = r.u(4);
            auto b2 = r.take(len);
            Reader q{b2};
            int sizes[] = {4, 7, 4, 4, 9, 9};
            c.valid = c.kind < 6 && len == uint32_t(sizes[c.kind]);
            if (c.valid) {
                switch (c.kind) {
                case 0:
                    c.v = {q.u(2), q.u(2)};
                    break;
                case 1:
                    c.v = {q.u(2), q.u(2), q.u(2), q.u(1)};
                    break;
                case 2:
                    c.v = {q.s(4)};
                    break;
                case 3:
                    c.v = {q.u(4)};
                    break;
                case 4:
                    c.v = {q.s(4), q.s(4), q.u(1)};
                    break;
                case 5:
                    c.v = {q.u(4), q.u(4), q.u(1)};
                    break;
                }
            }
            if (frame >= frames.size())
                warn("Control frame out of range");
            else {
                if (controls.count(frame))
                    warn("Duplicate control: first valid record wins");
                controls[frame].push_back(std::move(c));
            }
        }
        if (r.p != b.size())
            warn("Trailing paEX data");
        return true;
    }
    void masks(const Bytes &b) {
        Reader r{b};
        auto n = r.u(4);
        for (uint32_t i = 0; i < n; i++) {
            auto w = r.u(4), h = r.u(4), len = r.u(4);
            auto data = r.take(len);
            maps.push_back({w, h, std::move(data)});
        }
        n = r.u(4);
        for (uint32_t i = 0; i < n; i++) {
            auto f = r.u(4), m = r.u(4);
            if (f >= frames.size() || m >= maps.size() || maps[m].w != frames[f].w ||
                maps[m].h != frames[f].h || maps[m].packed.empty()) {
                warn("Invalid mask binding");
                continue;
            }
            if (bindings.count(f))
                warn("Duplicate mask binding");
            else
                bindings[f] = m;
        }
        if (r.p != b.size())
            warn("Trailing paMD data");
    }
    void metadataParse(const std::vector<Bytes> &texts);
    Bytes mask(int frame) {
        auto it = bindings.find(frame);
        if (it == bindings.end())
            return {};
        int id = it->second;
        if (maskCache.count(id))
            return maskCache[id];
        auto &m = maps[id];
        if (m.packed.empty())
            return {};
        try {
            size_t expected = size_t(m.w) * m.h * 2;
            auto bytes = inflate(m.packed, expected);
            require(bytes.size() == expected, "Invalid mask size");
            for (size_t p = 0; p < bytes.size(); p += 2) {
                int word = (bytes[p] << 8) | bytes[p + 1];
                if (word && (!(word & 0x8000) || (word & 32767) >= maskCount)) {
                    bytes[p] = bytes[p + 1] = 0;
                    warn("Invalid mask index: original color retained");
                }
            }
            if (bytes.size() <= CacheLimit / 2) {
                while (maskBytes + bytes.size() > CacheLimit / 2) {
                    auto i = maskCache.begin();
                    maskBytes -= i->second.size();
                    maskCache.erase(i);
                }
                maskBytes += bytes.size();
                maskCache[id] = bytes;
            }
            return bytes;
        } catch (const std::exception &) {
            warn("Invalid mask compression: original color retained");
            m.packed.clear();
            return {};
        }
    }
    size_t filteredSize(const Frame &f) const {
        int channels = header[9] == 0   ? 1
                       : header[9] == 2 ? 3
                       : header[9] == 3 ? 1
                       : header[9] == 4 ? 2
                       : header[9] == 6 ? 4
                                        : 0;
        require(channels > 0, "Invalid PNG color type");
        auto pass = [&](uint32_t x, uint32_t y, uint32_t dx, uint32_t dy) {
            uint64_t w = f.w > x ? (f.w - x + dx - 1) / dx : 0, h = f.h > y ? (f.h - y + dy - 1) / dy : 0;
            return w && h ? (((w * channels * header[8] + 7) / 8) + 1) * h : 0;
        };
        if (!header[12])
            return size_t(pass(0, 0, 1, 1));
        require(header[12] == 1, "Invalid PNG interlace");
        return size_t(pass(0, 0, 8, 8) + pass(4, 0, 8, 8) + pass(0, 4, 4, 8) + pass(2, 0, 4, 4) +
                      pass(0, 2, 2, 4) + pass(1, 0, 2, 2) + pass(0, 1, 1, 2));
    }
    Bytes raw(int frame) {
        if (rawCache.count(frame))
            return rawCache[frame];
        auto &f = frames[frame];
        {
            auto expected = filteredSize(f);
            require(expected <= Limit * 3, "PNG scanlines exceed memory budget");
            auto validated = inflate(f.data, expected);
            require(validated.size() == expected, "PNG scanline length mismatch");
        }
        Bytes png{137, 80, 78, 71, 13, 10, 26, 10}, ihdr;
        be(ihdr, f.w, 4);
        be(ihdr, f.h, 4);
        ihdr.insert(ihdr.end(), header.begin() + 8, header.end());
        chunk(png, "IHDR", ihdr);
        png.insert(png.end(), colors.begin(), colors.end());
        chunk(png, "IDAT", f.data);
        chunk(png, "IEND", {});
        int w, h, c;
        auto data = stbi_load_from_memory(png.data(), int(png.size()), &w, &h, &c, 4);
        require(data != nullptr, "PNG frame decode failed");
        Bytes bytes(data, data + size_t(w) * h * 4);
        stbi_image_free(data);
        if (bytes.size() <= CacheLimit) {
            while (rawBytes + bytes.size() > CacheLimit) {
                auto i = rawCache.begin();
                rawBytes -= i->second.size();
                rawCache.erase(i);
            }
            rawBytes += bytes.size();
            rawCache[frame] = bytes;
        }
        return bytes;
    }
    void means() {
        for (auto &b : bindings) {
            auto words = mask(b.first);
            if (words.empty())
                continue;
            auto bytes = raw(b.first);
            for (size_t i = 0; i < words.size(); i += 2) {
                int word = (words[i] << 8) | words[i + 1];
                if (!(word & 0x8000))
                    continue;
                auto &sum = sums[word & 32767];
                auto p = i * 2;
                double a = bytes[p + 3];
                for (int c = 0; c < 3; c++)
                    sum[c] += bytes[p + c] * a;
                sum[3] += a;
            }
        }
    }
    bool valid(const Control &c, int frame) const {
        if (!c.valid)
            return false;
        auto target = [&](int64_t n) { return n >= start && n <= end; };
        if (c.kind == 0)
            return true;
        if (c.kind == 2)
            return target(int64_t(frame) + c.v[0]);
        if (c.kind == 3)
            return target(c.v[0]);
        auto index = c.v[c.kind == 1 ? 3 : 2];
        if (index < 0 || size_t(index) >= distributions.size() || !distributions[index].valid)
            return false;
        auto value = [&](int64_t n) { return c.kind == 1 ? n >= 0 : target(n + (c.kind == 4 ? frame : 0)); };
        auto &d = distributions[index];
        if (d.kind == 4)
            return std::all_of(d.items.begin(), d.items.end(),
                               [&](auto item) { return !item.second || value(item.first); });
        return c.v[0] <= c.v[1] && value(c.v[0]) && value(c.v[1]);
    }
    uint64_t uniform(uint64_t n) { return std::uniform_int_distribution<uint64_t>(0, n - 1)(rng); }
    int64_t sample(int index, int64_t min, int64_t max) {
        auto &d = distributions[index];
        if (d.kind == 4) {
            uint64_t total = 0;
            for (auto i : d.items)
                total += i.second;
            auto draw = uniform(total);
            for (auto i : d.items) {
                if (draw < i.second)
                    return i.first;
                draw -= i.second;
            }
        }
        uint64_t n = uint64_t(max - min) + 1;
        if (!d.kind)
            return min + uniform(n);
        uint64_t peak = d.kind == 1 ? (n + 1) / 2 : n;
        for (;;) {
            auto i = uniform(n);
            auto weight = d.kind == 1 ? std::min(i + 1, n - i) : d.kind == 2 ? n - i : i + 1;
            if (uniform(peak) < weight)
                return min + i;
        }
    }
    static std::array<unsigned char, 3> hue(const unsigned char *p, double offset, double ds = 0, double dv = 0) {
        if (!std::isfinite(offset)) offset = 0;
        ds = std::isfinite(ds) ? std::clamp(ds,-1.0,1.0) : 0;
        dv = std::isfinite(dv) ? std::clamp(dv,-1.0,1.0) : 0;
        offset = fmod(offset,360);
        if (offset == 0 && ds == 0 && dv == 0) return {p[0],p[1],p[2]};
        double high = std::max({p[0],p[1],p[2]}), low = std::min({p[0],p[1],p[2]}), chroma = high-low;
        double h = chroma == 0 ? 0 : high == p[0] ? (p[1]-p[2])/chroma : high == p[1] ? (p[2]-p[0])/chroma+2 : (p[0]-p[1])/chroma+4;
        h = fmod(fmod(h+offset/60,6)+6,6);
        double sat = std::clamp((high == 0 ? 0 : chroma/high)+ds,0.0,1.0), val = std::clamp(high+dv*255,0.0,255.0);
        double c = val*sat, m = val-c, x = c*(1-fabs(fmod(h,2)-1));
        double a[6][3] = {{c,x,0},{x,c,0},{0,c,x},{0,x,c},{x,0,c},{c,0,x}};
        return {static_cast<unsigned char>(std::clamp(floor(a[int(h)][0]+m+.5+1e-10),0.0,255.0)),
                static_cast<unsigned char>(std::clamp(floor(a[int(h)][1]+m+.5+1e-10),0.0,255.0)),
                static_cast<unsigned char>(std::clamp(floor(a[int(h)][2]+m+.5+1e-10),0.0,255.0))};
    }
    void dispose() {
        auto &f = frames[state.frame];
        if (f.dispose == 2) {
            state.pixels = std::move(state.previous);
            state.marks = std::move(state.previousMarks);
        } else if (f.dispose == 1)
            for (uint32_t y = f.y; y < f.y + f.h; y++) {
                size_t p = (size_t(y) * width + f.x) * 4;
                std::fill_n(state.pixels.begin() + p, f.w * 4, 0);
                std::fill_n(state.marks.begin() + p, f.w * 4, 0);
            }
        state.previous.clear();
        state.previousMarks.clear();
    }
    void draw(int frame) {
        auto &f = frames[frame];
        auto pixels = raw(frame), words = mask(frame);
        if (f.dispose == 2) {
            state.previous = state.pixels;
            state.previousMarks = state.marks;
        }
        for (uint32_t y = 0; y < f.h; y++)
            for (uint32_t x = 0; x < f.w; x++) {
                size_t s = (size_t(y) * f.w + x) * 4, d = (size_t(y + f.y) * width + x + f.x) * 4;
                int word = words.empty() ? 0 : (words[s / 2] << 8) | words[s / 2 + 1];
                auto rgb = hue(pixels.data() + s, word & 0x8000 ? offsets[word & 32767] : 0, word & 0x8000 ? saturationOffsets[word & 32767] : 0, word & 0x8000 ? valueOffsets[word & 32767] : 0);
                double sa = pixels[s + 3] / 255.0, da = state.pixels[d + 3] / 255.0, a = sa + da * (1 - sa);
                if (!f.blend || sa == 1) {
                    for (int c = 0; c < 3; c++)
                        state.pixels[d + c] = rgb[c];
                    state.pixels[d + 3] = pixels[s + 3];
                } else if (sa > 0) {
                    for (int c = 0; c < 3; c++)
                        state.pixels[d + c] = (unsigned char)floor(
                            (rgb[c] * sa + state.pixels[d + c] * da * (1 - sa)) / a + .5);
                    state.pixels[d + 3] = (unsigned char)floor(a * 255 + .5);
                }
                bool mark = (word & 0x8000) && (selected < 0 || (word & 32767) == selected);
                double coverage = (mark ? sa : 0) + (f.blend ? state.marks[d + 3] / 255.0 * (1 - sa) : 0);
                state.marks[d] = 255;
                state.marks[d + 1] = 80;
                state.marks[d + 2] = 210;
                state.marks[d + 3] = (unsigned char)floor(coverage * 255 + .5);
            }
        state.frame = frame;
    }
    void remember() {
        auto size = state.size();
        if (size > CacheLimit)
            return;
        auto old = cache.find(state.frame);
        if (old != cache.end()) {
            cacheBytes -= old->second.state.size();
            cache.erase(old);
        }
        cache[state.frame] = {state, ++stamp};
        cacheBytes += size;
        while (cacheBytes > CacheLimit) {
            auto victim = cache.begin();
            uint64_t score = ~uint64_t(0);
            for (auto i = cache.begin(); i != cache.end(); ++i) {
                auto s = i->second.stamp + uint64_t(priority[i->first]) * 8;
                if (s < score) {
                    score = s;
                    victim = i;
                }
            }
            cacheBytes -= victim->second.state.size();
            cache.erase(victim);
        }
    }
    void seekCanvas(int target) {
        if (state.frame == target)
            return;
        auto hit = cache.find(target);
        if (hit != cache.end()) {
            hit->second.stamp = ++stamp;
            state = hit->second.state;
            return;
        }
        if (state.frame > target)
            state = State();
        for (auto &c : cache)
            if (c.first < target && c.first > state.frame)
                state = c.second.state;
        if (state.frame < 0) {
            state.pixels.assign(size_t(width) * height * 4, 0);
            state.marks = state.pixels;
        }
        for (int i = state.frame + 1; i <= target; i++) {
            if (state.frame >= 0)
                dispose();
            draw(i);
            if (i == target || priority.count(i) || i % 16 == 0)
                remember();
        }
    }
    void enter(int frame) {
        seekCanvas(frame);
        current = frame;
        visit = Control();
        bool found = false;
        auto it = controls.find(frame);
        if (it != controls.end()) {
            for (auto &c : it->second)
                if (valid(c, frame)) {
                    visit = c;
                    found = true;
                    break;
                }
            if (!found)
                warn("Invalid frame control: 10 ms and sequential playback");
        }
        double num = frames[frame].num, den = frames[frame].den;
        if (it != controls.end() && !found) {
            num = 1;
            den = 100;
        } else if (visit.valid && visit.kind == 0) {
            num = visit.v[0];
            den = visit.v[1];
        } else if (visit.valid && visit.kind == 1) {
            num = sample(int(visit.v[3]), visit.v[0], visit.v[1]);
            den = visit.v[2];
        }
        remaining = num / (den ? den : 100);
        if (num > 0) {
            visible = frame;
            presented = state.pixels;
            presentedMarks = state.marks;
            revision++;
        }
    }
    void advance() {
        if (ended || current < 0)
            return;
        int64_t target = int64_t(current) + 1;
        bool jump = visit.valid && visit.kind >= 2;
        if (jump) {
            if (visit.kind == 2 || visit.kind == 3)
                target = visit.v[0] + (visit.kind == 2 ? current : 0);
            else
                target = sample(int(visit.v[2]), visit.v[0], visit.v[1]) + (visit.kind == 4 ? current : 0);
            priority[int(target)] = std::min(12, priority[int(target)] + 1);
        } else if (target > end) {
            completed++;
            if (repeat && completed >= repeat) {
                ended = true;
                return;
            }
            state = State();
            target = start;
        }
        enter(int(target));
    }
    void tick(double seconds) {
        if (ended || current < 0)
            return;
        remaining -= std::max(0.0, seconds);
        auto begin = std::chrono::steady_clock::now();
        int visits = 0;
        while (remaining <= 0 && !ended) {
            double debt = remaining;
            advance();
            remaining += debt;
            if (++visits >= 128 || std::chrono::steady_clock::now() - begin > std::chrono::milliseconds(8)) {
                if (remaining <= 0)
                    warn("Playback visit budget reached; playback remains interruptible");
                break;
            }
        }
    }
    void restart(int which) {
        clip = which >= 0 && size_t(which) < clips.size() ? which : -1;
        start = clip < 0 ? 0 : clips[clip].start;
        end = clip < 0 ? int(frames.size()) - 1 : clips[clip].end;
        repeat = clip < 0 ? plays : clips[clip].plays;
        completed = 0;
        ended = false;
        visible = -1;
        current = -1;
        state = State();
        presented.clear();
        presentedMarks.clear();
        revision++;
        enter(start);
        tick(0);
    }
    void invalidate() {
        cache.clear();
        cacheBytes = 0;
        state = State();
        restart(clip);
    }
};
void Player::metadataParse(const std::vector<Bytes> &texts) {
    const Bytes *chosen = nullptr;
    for (auto &b : texts) {
        auto zero = std::find(b.begin(), b.end(), 0);
        if (std::string(b.begin(), zero) != "PAPNG.Metadata")
            continue;
        if (chosen) {
            warn("Duplicate PAPNG.Metadata ignored");
            return;
        }
        chosen = &b;
    }
    if (!chosen)
        return;
    try {
        Reader r{*chosen};
        while (r.u(1)) {
        }
        auto compression = r.u(1), method = r.u(1);
        require(compression <= 1 && !method, "Invalid iTXt");
        for (int i = 0; i < 2; i++)
            while (r.u(1)) {
            }
        auto rawText = r.take(chosen->size() - r.p);
        if (compression)
            rawText = inflate(rawText, 8 * 1024 * 1024);
        require(rawText.size() <= 8 * 1024 * 1024, "Metadata too large");
        std::string text(rawText.begin(), rawText.end());
        auto root = Json5(text).parse();
        require(root.type == Json::Object && root["schema_version"].uint() &&
                    root["schema_version"].number == 1,
                "Unsupported metadata schema");
        for (auto key : {"clips", "mask_groups"})
            require(!root.has(key) || root[key].type == Json::Array, "Invalid metadata array");
        metadata = text;
        for (auto &c : root["clips"].array) {
            auto &id = c["id"];
            auto &name = c.has("name") ? c["name"] : id;
            auto &a = c["start_frame"];
            auto &b = c["end_frame"];
            auto &playsValue = c["play_count"];
            if (id.type != Json::String || id.text.empty() || name.type != Json::String || !a.uint() ||
                !b.uint() || !playsValue.uint() || a.number > b.number || b.number >= frames.size() ||
                std::any_of(clips.begin(), clips.end(), [&](auto &x) { return x.id == id.text; })) {
                warn("Invalid clip ignored");
                continue;
            }
            clips.push_back(
                {name.text, id.text, uint32_t(a.number), uint32_t(b.number), uint32_t(playsValue.number)});
        }
        maskNames.resize(maskCount);
        std::map<std::string, bool> seen;
        for (auto &g : root["mask_groups"].array) {
            auto &id = g["id"];
            auto &name = g.has("name") ? g["name"] : id;
            auto &indices = g["palette_indices"];
            bool valid = id.type == Json::String && !id.text.empty() && !seen.count(id.text) &&
                         name.type == Json::String && indices.type == Json::Array;
            std::map<int, bool> used;
            for (auto &index : indices.array) {
                if (!index.uint() || index.number >= maskCount || used.count(int(index.number))) {
                    valid = false;
                    break;
                }
                used[int(index.number)] = true;
            }
            if (!valid) {
                warn("Invalid mask group ignored");
                continue;
            }
            seen[id.text] = true;
            for (auto &i : used) {
                if (maskNames[i.first].size() < 256) {
                    if (!maskNames[i.first].empty()) maskNames[i.first] += " / ";
                    maskNames[i.first] = label(maskNames[i.first] + label(name.text));
                }
            }
        }
        if (!root.has("sockets"))
            return;
        try {
            auto &s = root["sockets"];
            require(s.type == Json::Object && s["definitions"].type == Json::Array &&
                        s["frames"].type == Json::Array,
                    "Invalid sockets");
            for (auto &d : s["definitions"].array) {
                auto &n = d["name"];
                require(n.type == Json::String && !n.text.empty() &&
                            std::find(socketNames.begin(), socketNames.end(), n.text) == socketNames.end(),
                        "Invalid socket name");
                socketNames.push_back(n.text);
            }
            if (socketNames.empty()) {
                require(s["frames"].array.empty(), "Empty socket definitions");
                return;
            }
            for (auto &f : s["frames"].array) {
                auto &index = f["frame_index"];
                auto &positions = f["positions"];
                if (!index.uint() || index.number >= frames.size() || positions.type != Json::Array ||
                    positions.array.size() != socketNames.size()) {
                    warn("Invalid socket frame ignored");
                    continue;
                }
                std::vector<Pose> values;
                for (auto &p : positions.array) {
                    if (p.type != Json::Array || p.array.size() < 2 || p.array.size() > 3 ||
                        !std::all_of(p.array.begin(), p.array.end(), [](auto &n) { return n.finite(); }))
                        break;
                    values.push_back(
                        {p.array[0].number, p.array[1].number, p.array.size() == 3 ? p.array[2].number : 0});
                }
                if (values.size() != socketNames.size() || poses.count(int(index.number))) {
                    warn("Invalid or duplicate socket pose ignored");
                    continue;
                }
                poses[int(index.number)] = values;
            }
            require(poses.count(0), "Missing socket frame zero");
        } catch (const std::exception &e) {
            warn(e.what());
            socketNames.clear();
            poses.clear();
        }
    } catch (const std::exception &e) {
        warn(std::string("Metadata ignored: ") + e.what());
    }
}
} // namespace papng
namespace {
papng::Player *player(void *h) { return static_cast<papng::Player *>(h); }
template <class F> void guarded(void *h, F f) {
    if (!h)
        return;
    try {
        f(*player(h));
    } catch (const std::exception &e) {
        player(h)->error = e.what();
        player(h)->ended = true;
    } catch (...) {
        player(h)->error = "Unexpected playback error";
        player(h)->ended = true;
    }
}
} // namespace
extern "C" {
void *pp_open(const unsigned char *bytes, int length) {
    try {
        if (!bytes || length < 0 || size_t(length) > papng::Limit)
            throw std::runtime_error("Invalid file size");
        return new papng::Player(papng::Bytes(bytes, bytes + length));
    } catch (const std::exception &e) {
        auto p = new papng::Player();
        p->error = e.what();
        return p;
    } catch (...) {
        return nullptr;
    }
}
void pp_close(void *h) { delete player(h); }
const char *pp_error(void *h) { return h ? player(h)->error.c_str() : "Unable to allocate document"; }
const char *pp_warnings(void *h) { return h ? player(h)->warnings.c_str() : ""; }
const char *pp_metadata(void *h) { return h ? player(h)->metadata.c_str() : ""; }
int pp_get(void *h, int field) {
    if (!h)
        return 0;
    auto &p = *player(h);
    switch (field) {
    case 0:
        return p.width;
    case 1:
        return p.height;
    case 2:
        return int(p.frames.size());
    case 3:
        return p.maskCount;
    case 4:
        return p.visible;
    case 5:
        return p.ended;
    case 6:
        return p.revision;
    case 7:
        return int(p.socketNames.size());
    case 8:
        return int(p.clips.size());
    case 9:
        return p.source;
    default:
        return 0;
    }
}
const unsigned char *pp_pixels(void *h) {
    return h && !player(h)->presented.empty() ? player(h)->presented.data() : nullptr;
}
const unsigned char *pp_marks(void *h) {
    return h && !player(h)->presentedMarks.empty() ? player(h)->presentedMarks.data() : nullptr;
}
void pp_tick(void *h, double seconds) {
    guarded(h, [&](auto &p) {
        if (p.error.empty() && std::isfinite(seconds))
            p.tick(seconds);
    });
}
void pp_step(void *h) {
    guarded(h, [](auto &p) {
        if (p.error.empty()) {
            p.advance();
            p.tick(0);
        }
    });
}
void pp_restart(void *h, int clip) {
    guarded(h, [&](auto &p) {
        if (p.error.empty())
            p.restart(clip);
    });
}
void pp_seek(void *h, int frame) {
    guarded(h, [&](auto &p) {
        if (p.error.empty() && frame >= p.start && frame <= p.end) {
            p.ended = false;
            p.completed = 0;
            p.enter(frame);
            p.tick(0);
        }
    });
}
void pp_mask_hsv(void *h, int index, double degrees, double saturation, double value) {
    guarded(h, [&](auto &p) {
        if (index < 0 || index >= p.maskCount) return;
        auto finite = [&](double n) { if (std::isfinite(n)) return n; p.warn("Non-finite HSV offset: component reset to zero"); return 0.0; };
        p.offsets[index] = fmod(finite(degrees),360);
        p.saturationOffsets[index] = std::clamp(finite(saturation),-1.0,1.0);
        p.valueOffsets[index] = std::clamp(finite(value),-1.0,1.0);
        p.invalidate();
    });
}
void pp_mask(void *h, int index, double degrees) {
    if (h && index >= 0 && index < player(h)->maskCount)
        pp_mask_hsv(h,index,degrees,player(h)->saturationOffsets[index],player(h)->valueOffsets[index]);
}
double pp_offset(void *h, int index) {
    return h && index >= 0 && index < player(h)->maskCount ? player(h)->offsets[index] : 0;
}
void pp_select_mask(void *h, int index) {
    guarded(h, [&](auto &p) {
        if (p.error.empty() && index >= -1 && index < p.maskCount) {
            p.selected = index;
            p.invalidate();
        }
    });
}
const char *pp_name(void *h, int kind, int index) {
    if (!h || index < 0)
        return "";
    auto &p = *player(h);
    if (kind == 0 && index < p.maskCount) {
        p.nameBuffer = std::to_string(index);
        if (!p.maskNames[index].empty())
            p.nameBuffer += " · " + p.maskNames[index];
        return p.nameBuffer.c_str();
    }
    if (kind == 1 && size_t(index) < p.socketNames.size())
        return (p.nameBuffer=papng::label(p.socketNames[index])).c_str();
    if (kind == 2 && size_t(index) < p.clips.size())
        return (p.nameBuffer=papng::label(p.clips[index].name)).c_str();
    return "";
}
int pp_socket(void *h, int index, double *xyz) {
    if (!h || !xyz)
        return 0;
    auto &p = *player(h);
    if (p.visible < 0 || index < 0 || size_t(index) >= p.socketNames.size())
        return 0;
    auto it = p.poses.upper_bound(p.visible);
    if (it == p.poses.begin())
        return 0;
    --it;
    auto pose = it->second[index];
    xyz[0] = pose.x;
    xyz[1] = pose.y;
    xyz[2] = pose.r;
    return 1;
}
int pp_hint(void *h, int kind, double *values) {
    if (!h || !values || !player(h)->hints.count(kind))
        return 0;
    auto &v = player(h)->hints[kind];
    std::copy(v.begin(), v.end(), values);
    return 1;
}
uint32_t pp_mean(void *h, int mask) {
    if (!h || mask < 0 || mask >= player(h)->maskCount)
        return 0;
    auto &v = player(h)->sums[mask];
    if (v[3] <= 0)
        return 0;
    uint32_t c = 0;
    for (int i = 0; i < 3; i++)
        c = (c << 8) | uint32_t(floor(v[i] / v[3] + .5));
    return (c << 8) | 255;
}
}
