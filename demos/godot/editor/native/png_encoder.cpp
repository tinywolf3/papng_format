// Lossless RGBA8 PNG scanline selection. Compression uses Godot's bundled zlib.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <vector>
using namespace godot;

namespace {
int paeth(int a, int b, int c) {
    const int p = a + b - c, da = std::abs(p - a), db = std::abs(p - b), dc = std::abs(p - c);
    return da <= db && da <= dc ? a : db <= dc ? b : c;
}
}
class PapngPngEncoder : public RefCounted {
    GDCLASS(PapngPngEncoder, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("encode", "rgba", "width", "height"), &PapngPngEncoder::encode);
    }
public:
    PackedByteArray encode(const PackedByteArray &rgba, int64_t width, int64_t height) {
        constexpr int64_t max_pixels = 32LL * 1024 * 1024;
        if (width <= 0 || height <= 0 || width > max_pixels / height || rgba.size() != width * height * 4)
            return {};
        const int64_t stride = width * 4, row_size = stride + 1, size = row_size * height;
        PackedByteArray scanlines, adaptive, best;
        if (scanlines.resize(size) != OK || adaptive.resize(size) != OK) return {};
        auto *rows = scanlines.ptrw();
        auto *chosen = adaptive.ptrw();
        const auto *source = rgba.ptr();
        std::vector<uint64_t> scores(height, std::numeric_limits<uint64_t>::max());
        // Keep only one candidate plus the adaptive buffer, not six full images.
        for (int filter = 0; filter <= 5; ++filter) {
            if (filter < 5) {
                for (int64_t y = 0; y < height; ++y) {
                    auto *row = rows + y * row_size;
                    const auto *current = source + y * stride;
                    const auto *previous = y ? current - stride : nullptr;
                    row[0] = uint8_t(filter);
                    uint64_t score = 0;
                    for (int64_t x = 0; x < stride; ++x) {
                        const int a = x >= 4 ? current[x - 4] : 0;
                        const int b = previous ? previous[x] : 0;
                        const int c = previous && x >= 4 ? previous[x - 4] : 0;
                        const int prediction = filter == 0 ? 0 : filter == 1 ? a : filter == 2 ? b :
                            filter == 3 ? (a + b) / 2 : paeth(a, b, c);
                        const uint8_t value = uint8_t(current[x] - prediction);
                        row[x + 1] = value;
                        score += std::min(int(value), 256 - int(value));
                    }
                    if (score < scores[y]) {
                        scores[y] = score;
                        std::memcpy(chosen + y * row_size, row, row_size);
                    }
                }
            }
            // Mode 1 is zlib/DEFLATE. The editor sets its compression level to 9.
            auto compressed = (filter == 5 ? adaptive : scanlines).compress(1);
            if (compressed.is_empty()) return {};
            if (best.is_empty() || compressed.size() < best.size()) best = compressed;
        }
        return best;
    }
};
void register_png_encoder() { ClassDB::register_class<PapngPngEncoder>(); }
