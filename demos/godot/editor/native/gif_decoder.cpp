#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <gif_lib.h>
#include <algorithm>
#include <chrono>
#include <cstring>
#include <memory>
#include <vector>

using namespace godot;
namespace {
constexpr int64_t GIF_INPUT_BUDGET = 128LL * 1024 * 1024;
constexpr int64_t MAX_PIXELS = 32LL * 1024 * 1024;
constexpr int64_t MAX_OUTPUT = 256LL * 1024 * 1024;
struct Reader {
    const uint8_t *bytes;
    int64_t size, position = 0;
};
int read_bytes(GifFileType *gif, GifByteType *out, int count) {
    auto &reader = *static_cast<Reader *>(gif->UserData);
    if (count < 0 || count > reader.size - reader.position) return 0;
    std::memcpy(out, reader.bytes + reader.position, count);
    reader.position += count;
    return count;
}
struct CloseGif {
    void operator()(GifFileType *gif) const { int error; DGifCloseFile(gif, &error); }
};
Dictionary failure(const String &message) {
    Dictionary result; result["error"] = message; return result;
}
Dictionary gif_failure(GifFileType *gif) {
    const char *message = GifErrorString(gif->Error);
    return failure(String("GIF 디코딩 실패: ") + (message ? message : "잘못된 데이터"));
}
GraphicsControlBlock default_control() { return {0, false, 0, NO_TRANSPARENT_COLOR}; }
}

class PapngGifDecoder : public RefCounted {
    GDCLASS(PapngGifDecoder, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("decode", "bytes", "first_only", "cancel"), &PapngGifDecoder::decode);
    }
public:
    Dictionary decode(const PackedByteArray &bytes, bool first_only, const Callable &cancel) {
        if (bytes.size() < 13 || bytes.size() > GIF_INPUT_BUDGET) return failure("GIF 입력이 비어 있거나 128 MiB 예산을 초과합니다.");
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
        auto interrupted = [&]() {
            return std::chrono::steady_clock::now() >= deadline || (cancel.is_valid() && bool(cancel.call()));
        };
        Reader reader{bytes.ptr(), bytes.size()};
        int error = 0;
        std::unique_ptr<GifFileType, CloseGif> owner(DGifOpen(&reader, read_bytes, &error));
        if (!owner) return failure("올바른 GIF 파일이 아닙니다.");
        auto *gif = owner.get();
        const int width = gif->SWidth, height = gif->SHeight;
        const int64_t pixels = int64_t(width) * height, frame_bytes = pixels * 4;
        if (width <= 0 || height <= 0 || pixels > MAX_PIXELS) return failure("GIF 캔버스가 잘못되었거나 32 메가픽셀 예산을 초과합니다.");
        std::vector<uint8_t> canvas(frame_bytes, 0), previous;
        Array frames;
        int plays = 1;
        auto control = default_control();
        auto fill_rect = [&](int left, int top, int w, int h, bool transparent) {
            uint8_t color[4] = {0, 0, 0, 0};
            if (!transparent && gif->SColorMap && gif->SBackGroundColor < gif->SColorMap->ColorCount) {
                const auto &c = gif->SColorMap->Colors[gif->SBackGroundColor];
                color[0] = c.Red; color[1] = c.Green; color[2] = c.Blue; color[3] = 255;
            }
            for (int y = top; y < top + h; ++y)
                for (int x = left; x < left + w; ++x)
                    std::memcpy(canvas.data() + (int64_t(y) * width + x) * 4, color, 4);
        };
        while (true) {
            if (interrupted()) return failure("GIF 불러오기가 취소되었거나 60초를 초과했습니다.");
            GifRecordType type;
            if (DGifGetRecordType(gif, &type) == GIF_ERROR) return gif_failure(gif);
            if (type == TERMINATE_RECORD_TYPE) break;
            if (type == EXTENSION_RECORD_TYPE) {
                int code;
                GifByteType *block = nullptr;
                if (DGifGetExtension(gif, &code, &block) == GIF_ERROR) return gif_failure(gif);
                if (code == PLAINTEXT_EXT_FUNC_CODE) return failure("텍스트 그래픽이 포함된 GIF는 지원하지 않습니다.");
                if (code == GRAPHICS_EXT_FUNC_CODE) {
                    if (!block || block[0] != 4 || DGifExtensionToGCB(block[0], block + 1, &control) == GIF_ERROR)
                        return failure("GIF 프레임 제어 정보가 잘못되었습니다.");
                }
                const bool loop = code == APPLICATION_EXT_FUNC_CODE && block && block[0] == 11 &&
                    (!std::memcmp(block + 1, "NETSCAPE2.0", 11) || !std::memcmp(block + 1, "ANIMEXTS1.0", 11));
                while (block) {
                    if (interrupted()) return failure("GIF 불러오기가 취소되었거나 60초를 초과했습니다.");
                    if (DGifGetExtensionNext(gif, &block) == GIF_ERROR) return gif_failure(gif);
                    if (loop && block && block[0] == 3 && block[1] == 1) {
                        const int repeats = block[2] | (block[3] << 8);
                        plays = repeats ? repeats + 1 : 0;
                    }
                }
                continue;
            }
            if (type != IMAGE_DESC_RECORD_TYPE) return failure("알 수 없는 GIF 블록입니다.");
            // Streaming headers avoid allocating SavedImages for the whole animation.
            if (DGifGetImageHeader(gif) == GIF_ERROR) return gif_failure(gif);
            const auto &image = gif->Image;
            if (image.Width <= 0 || image.Height <= 0 || image.Left + image.Width > width || image.Top + image.Height > height)
                return failure("GIF 프레임 영역이 캔버스를 벗어납니다.");
            if ((int64_t(frames.size()) + 1) * (frame_bytes + 512) > MAX_OUTPUT)
                return failure("GIF 애니메이션이 256 MiB 편집 예산을 초과합니다.");
            auto *palette = image.ColorMap ? image.ColorMap : gif->SColorMap;
            if (!palette) return failure("GIF 프레임에 색상표가 없습니다.");
            if (frames.is_empty()) fill_rect(0, 0, width, height, control.TransparentColor != NO_TRANSPARENT_COLOR);
            if (control.DisposalMode == DISPOSE_PREVIOUS) previous = canvas;
            std::vector<GifPixelType> row(image.Width);
            auto scanline = [&](int y) -> bool {
                if (DGifGetLine(gif, row.data(), image.Width) == GIF_ERROR) return false;
                for (int x = 0; x < image.Width; ++x) {
                    int index = row[x];
                    if (index == control.TransparentColor) continue;
                    if (index >= palette->ColorCount) { gif->Error = D_GIF_ERR_IMAGE_DEFECT; return false; }
                    const auto &color = palette->Colors[index];
                    uint8_t *pixel = canvas.data() + (int64_t(image.Top + y) * width + image.Left + x) * 4;
                    pixel[0] = color.Red; pixel[1] = color.Green; pixel[2] = color.Blue; pixel[3] = 255;
                }
                return true;
            };
            const int starts[] = {0, 4, 2, 1}, steps[] = {8, 8, 4, 2};
            for (int pass = 0; pass < (image.Interlace ? 4 : 1); ++pass) {
                for (int y = image.Interlace ? starts[pass] : 0; y < image.Height; y += image.Interlace ? steps[pass] : 1) {
                    if ((y & 63) == 0 && interrupted()) return failure("GIF 불러오기가 취소되었거나 60초를 초과했습니다.");
                    if (!scanline(y)) return gif_failure(gif);
                }
            }
            PackedByteArray rgba; rgba.resize(frame_bytes);
            std::memcpy(rgba.ptrw(), canvas.data(), frame_bytes);
            Dictionary frame; frame["rgba"] = rgba; frame["num"] = std::max(1, control.DelayTime); frame["den"] = 100;
            frames.append(frame);
            if (first_only) break;
            if (control.DisposalMode == DISPOSE_BACKGROUND)
                fill_rect(image.Left, image.Top, image.Width, image.Height, control.TransparentColor != NO_TRANSPARENT_COLOR);
            else if (control.DisposalMode == DISPOSE_PREVIOUS) canvas.swap(previous);
            previous.clear();
            control = default_control();
        }
        if (frames.is_empty()) return failure("GIF에 이미지 프레임이 없습니다.");
        Dictionary result;
        result["width"] = width; result["height"] = height; result["frames"] = frames; result["plays"] = plays;
        result["decoder"] = "giflib 6.1.3";
        return result;
    }
};

void register_png_encoder();
static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_class<PapngGifDecoder>();
        register_png_encoder();
    }
}
static void uninitialize(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT papng_gif_init(GDExtensionInterfaceGetProcAddress proc,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(proc, library, initialization);
    init.register_initializer(initialize); init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
