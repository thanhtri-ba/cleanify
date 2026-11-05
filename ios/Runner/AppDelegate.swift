import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    PhotoEditsChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Kênh nền tảng "cleanify/photo_edits": ảnh nào đã chỉnh sửa trong ứng dụng Ảnh
/// và thumbnail của BẢN GỐC (chưa chỉnh). Không tải ảnh từ iCloud.
final class PhotoEditsChannel {
  private static let queue = DispatchQueue(label: "cleanify.photo_edits", qos: .utility)

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cleanify/photo_edits", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let ids = args["ids"] as? [String] else {
        result(FlutterError(code: "bad_args", message: "thiếu ids", details: nil))
        return
      }
      switch call.method {
      case "editedIds":
        queue.async {
          let out = editedIds(ids)
          DispatchQueue.main.async { result(out) }
        }
      case "storage":
        queue.async {
          let out = storage()
          DispatchQueue.main.async { result(out) }
        }
      case "screenshotIds":
        queue.async {
          let out = screenshotIds()
          DispatchQueue.main.async { result(out) }
        }
      case "fileSizes":
        queue.async {
          let out = fileSizes(ids)
          DispatchQueue.main.async { result(out) }
        }
      case "originalThumbs":
        let side = (args["size"] as? Int) ?? 128
        queue.async {
          let out = originalThumbs(ids, side: side)
          DispatchQueue.main.async { result(out) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func fetch(_ ids: [String]) -> [PHAsset] {
    let r = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    var out: [PHAsset] = []
    r.enumerateObjects { asset, _, _ in out.append(asset) }
    return out
  }

  /// Ảnh có resource `adjustmentData` là ảnh đã chỉnh sửa (bản gốc vẫn nằm trong
  /// cùng asset, không phải một asset riêng).
  private static func editedIds(_ ids: [String]) -> [String] {
    var out: [String] = []
    for asset in fetch(ids) {
      let types = PHAssetResource.assetResources(for: asset).map { $0.type }
      if types.contains(.adjustmentData) { out.append(asset.localIdentifier) }
    }
    return out
  }

  /// Dung lượng thiết bị: tổng và còn trống (byte). "Còn trống" dùng
  /// volumeAvailableCapacityForImportantUsage, khớp số iOS hiển thị trong Cài đặt.
  private static func storage() -> [String: Int] {
    var out: [String: Int] = [:]
    let url = URL(fileURLWithPath: NSHomeDirectory())
    if let v = try? url.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]) {
      if let t = v.volumeTotalCapacity { out["total"] = t }
      if let f = v.volumeAvailableCapacityForImportantUsage { out["free"] = Int(f) }
    }
    return out
  }

  /// localIdentifier của mọi ảnh chụp màn hình (iOS tự gắn subtype), mới nhất trước.
  private static func screenshotIds() -> [String] {
    let opts = PHFetchOptions()
    opts.predicate = NSPredicate(
      format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
    opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    var out: [String] = []
    PHAsset.fetchAssets(with: .image, options: opts).enumerateObjects { asset, _, _ in
      out.append(asset.localIdentifier)
    }
    return out
  }

  /// Dung lượng file (byte) của từng asset, lấy từ metadata PHAssetResource nên
  /// KHÔNG tải gì từ iCloud. Lấy resource lớn nhất trong nhóm video (bản đã chỉnh
  /// và bản gốc cùng tồn tại thì tính bản lớn hơn). Khóa "fileSize" không nằm trong
  /// header công khai nhưng là KVC phổ biến; kiểm tra respondsToSelector để không
  /// bị ngoại lệ nếu iOS đổi.
  private static func fileSizes(_ ids: [String]) -> [String: Int] {
    var out: [String: Int] = [:]
    let sel = Selector(("fileSize"))
    for asset in fetch(ids) {
      var best = 0
      for res in PHAssetResource.assetResources(for: asset) {
        guard res.type == .video || res.type == .fullSizeVideo || res.type == .photo,
              res.responds(to: sel),
              let n = res.value(forKey: "fileSize") as? NSNumber else { continue }
        best = max(best, n.intValue)
      }
      out[asset.localIdentifier] = best
    }
    return out
  }

  /// JPEG (chất lượng 0.7) của bản gốc, cạnh tối thiểu [side] px, đã nướng
  /// orientation vào pixel để bộ giải mã Dart không cần đọc EXIF.
  private static func originalThumbs(_ ids: [String], side: Int) -> [String: FlutterStandardTypedData] {
    let opts = PHImageRequestOptions()
    opts.version = .original
    opts.deliveryMode = .highQualityFormat
    opts.resizeMode = .fast
    opts.isNetworkAccessAllowed = false
    opts.isSynchronous = true
    let target = CGSize(width: side, height: side)
    var out: [String: FlutterStandardTypedData] = [:]
    for asset in fetch(ids) {
      autoreleasepool {
        PHImageManager.default().requestImage(
          for: asset, targetSize: target, contentMode: .aspectFill, options: opts
        ) { image, _ in
          guard let image = image else { return }
          let size = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
          let format = UIGraphicsImageRendererFormat.default()
          format.scale = 1
          let baked = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
          }
          if let data = baked.jpegData(compressionQuality: 0.7) {
            out[asset.localIdentifier] = FlutterStandardTypedData(bytes: data)
          }
        }
      }
    }
    return out
  }
}
