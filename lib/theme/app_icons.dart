/// Một icon vẽ tay trên lưới 24x24 (SVG, nét 1,75, đầu nét tròn). [body] là phần ruột
/// của thẻ svg; phần tử có class="a" là chi tiết nhấn (lime), còn lại theo màu chữ.
/// Vẽ bằng [AppIcon] (lib/theme/app_icon.dart).
class AppIconData {
  const AppIconData(this.name, this.body);
  final String name;
  final String body;
}

/// Bộ icon của app (bản vẽ riêng đã duyệt). Mọi icon trong UI lấy từ đây. Tên giữ theo
/// tên Icons của Material cũ để các màn hình không phải đổi.
class AppIcons {
  AppIcons._();

  static const _filter = AppIconData('filter', r'''<path d="M4 7h9"/><path d="M17 7h3"/><path d="M4 17h3"/><path d="M11 17h9"/><circle class="a" cx="15" cy="7" r="2"/><circle class="a" cx="9" cy="17" r="2"/>'''); 
  static const _bell = AppIconData('bell', r'''<path d="M6 17v-6a6 6 0 1112 0v6l1.5 2h-15z"/><path class="a" d="M10 21h4"/>''');
  static const _back = AppIconData('back', r'''<path d="M14.5 6l-6 6 6 6"/>''');
  static const _forward = AppIconData('forward', r'''<path d="M5 12h14"/><path d="M13 6l6 6-6 6"/>''');
  static const _chevron = AppIconData('chevron', r'''<path d="M9.5 6l6 6-6 6"/>''');
  static const _check = AppIconData('check', r'''<path d="M5 12.5l4.5 4.5L19 7.5"/>''');
  static const _checkCircle = AppIconData('checkCircle', r'''<circle cx="12" cy="12" r="9"/><path class="a" d="M8 12.3l2.7 2.7L16 9.6"/>''');
  static const _search = AppIconData('search', r'''<circle cx="11" cy="11" r="6.5"/><path class="a" d="M16 16l4 4"/>''');
  static const _sparkle = AppIconData('sparkle', r'''<path d="M10.5 6c.5 3.8 2.7 6 6.5 6.5-3.8.5-6 2.7-6.5 6.5-.5-3.8-2.7-6-6.5-6.5C7.8 12 10 9.8 10.5 6z"/><path class="a" d="M18.5 3v4M16.5 5h4"/>''');
  static const _clean = AppIconData('clean', r'''<g transform="rotate(38 12 12)"><path d="M12 3v8"/><path d="M8.4 11h7.2l1.3 7.6a1.4 1.4 0 0 1-1.4 1.6H8.5a1.4 1.4 0 0 1-1.4-1.6L8.4 11z"/><path class="a" d="M10.3 14.6v3M13.7 14.6v3"/></g>''');
  static const _trash = AppIconData('trash', r'''<path d="M5 7h14"/><path d="M9.5 7V5.8A1.8 1.8 0 0 1 11.3 4h1.4a1.8 1.8 0 0 1 1.8 1.8V7"/><path d="M6.5 7l.8 11a2 2 0 0 0 2 1.9h5.4a2 2 0 0 0 2-1.9L17.5 7"/><path class="a" d="M10.2 11v5M13.8 11v5"/>''');
  static const _copy = AppIconData('copy', r'''<rect x="8.5" y="8.5" width="11" height="11" rx="2.8"/><path class="a" d="M15.5 8.5V7A3 3 0 0 0 12.5 4H7A3 3 0 0 0 4 7v5.5A3 3 0 0 0 7 15.5h1.5"/>''');
  static const _compare = AppIconData('compare', r'''<rect x="4" y="9" width="11" height="11" rx="2.8"/><rect class="a" x="9" y="4" width="11" height="11" rx="2.8"/>''');
  static const _fingerprint = AppIconData('fingerprint', r'''<path d="M5 12.5v-.5a7 7 0 0 1 14 0v1"/><path d="M8 16V12a4 4 0 0 1 8 0v1.5c0 2-.4 3.8-1.2 5.5"/><path class="a" d="M12 12v3c0 1.8-.4 3.4-1 4.8"/>''');
  static const _home = AppIconData('home', r'''<path d="M4 11l8-6.5 8 6.5"/><path d="M6 9.5V19a1 1 0 0 0 1 1h3.5v-5h3v5H17a1 1 0 0 0 1-1V9.5"/>''');
  static const _image = AppIconData('image', r'''<rect x="4" y="5" width="16" height="14" rx="3.2"/><circle class="a" cx="9" cy="10" r="1.6"/><path d="M4.5 17l4.6-4.4 3.4 3.3 2.6-2.5 4.4 4"/>''');
  static const _images = AppIconData('images', r'''<rect x="3.5" y="8" width="13" height="12" rx="3"/><path d="M7 5h10a3 3 0 0 1 3 3v8"/><circle class="a" cx="8.6" cy="12.4" r="1.3"/><path d="M4 18l3.8-3.6 3 2.8 2.2-2 3 2.8"/>''');
  static const _info = AppIconData('info', r'''<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path class="a" d="M12 7.9h.01"/>''');
  static const _layers = AppIconData('layers', r'''<path d="M12 4l8 4.3-8 4.3-8-4.3L12 4z"/><path d="M4 12l8 4.3 8-4.3"/><path class="a" d="M4 15.7l8 4.3 8-4.3"/>''');
  static const _lock = AppIconData('lock', r'''<rect x="5" y="10.5" width="14" height="9.5" rx="3"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/><path class="a" d="M12 14.4v2"/>''');
  static const _lockOpen = AppIconData('lockOpen', r'''<rect x="5" y="10.5" width="14" height="9.5" rx="3"/><path d="M8 10.5V8a4 4 0 0 1 7.6-1.7"/><path class="a" d="M12 14.4v2"/>''');
  static const _more = AppIconData('more', r'''<circle cx="6" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18" cy="12" r="1.3"/>''');
  static const _pause = AppIconData('pause', r'''<rect x="7" y="5" width="3.4" height="14" rx="1.5"/><rect x="13.6" y="5" width="3.4" height="14" rx="1.5"/>''');
  static const _play = AppIconData('play', r'''<path d="M8 5.8v12.4a.8.8 0 0 0 1.2.7l10-6.2a.8.8 0 0 0 0-1.4l-10-6.2A.8.8 0 0 0 8 5.8z"/>''');
  static const _phone = AppIconData('phone', r'''<rect x="7" y="3" width="10" height="18" rx="3"/><path class="a" d="M10.6 18h2.8"/>''');
  static const _pie = AppIconData('pie', r'''<path d="M11 4.2A8.5 8.5 0 1 0 19.8 13H11V4.2z"/><path class="a" d="M14 3.7A8.5 8.5 0 0 1 20.3 10H14V3.7z"/>''');
  static const _refresh = AppIconData('refresh', r'''<path d="M19 12a7 7 0 1 1-2.1-5"/><path class="a" d="M19 4.5v4h-4"/>''');
  static const _clock = AppIconData('clock', r'''<circle cx="12" cy="12" r="9"/><path class="a" d="M12 7.5V12l3 2"/>''');
  static const _screenshot = AppIconData('screenshot', r'''<path d="M8 4H7a3 3 0 0 0-3 3v1M16 4h1a3 3 0 0 1 3 3v1M20 16v1a3 3 0 0 1-3 3h-1M8 20H7a3 3 0 0 1-3-3v-1"/><rect class="a" x="9" y="9" width="6" height="6" rx="1.6"/>''');
  static const _settings = AppIconData('settings', r'''<path d="M4 8h9M17 8h3M4 16h3M11 16h9"/><circle cx="15" cy="8" r="2"/><circle class="a" cx="9" cy="16" r="2"/>''');
  static const _shield = AppIconData('shield', r'''<path d="M12 3.5l7 2.6v5.4c0 4.2-2.8 7.3-7 9-4.2-1.7-7-4.8-7-9V6.1l7-2.6z"/><path class="a" d="M9 12l2.2 2.2L15 10.4"/>''');
  static const _storage = AppIconData('storage', r'''<path d="M4 14l2.1-7.4A2 2 0 0 1 8 5h8a2 2 0 0 1 1.9 1.6L20 14"/><rect x="4" y="14" width="16" height="6" rx="2.6"/><circle class="a" cx="16.4" cy="17" r=".9"/>''');
  static const _video = AppIconData('video', r'''<rect x="3.5" y="6.5" width="12" height="11" rx="3"/><path class="a" d="M15.5 10.6l4.3-2.4a.5.5 0 0 1 .7.4v6.8a.5.5 0 0 1-.7.4l-4.3-2.4"/>''');
  static const _warning = AppIconData('warning', r'''<path d="M12 4.2l9 15.3H3L12 4.2z"/><path class="a" d="M12 10v4"/><path class="a" d="M12 16.9h.01"/>''');
  static const _heart = AppIconData('heart', r'''<path d="M12 19.5s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7a4.3 4.3 0 0 1 7.5 2.5c0 5.6-7.5 10-7.5 10z"/>''');

  // ---- tên dùng trong app (giữ theo tên Icons cũ) ----
  static const arrowBackIosNewRounded = _back;
  static const arrowForwardRounded = _forward;
  static const autoAwesomeOutlined = _sparkle;
  static const check = _check;
  static const checkCircleOutline = _checkCircle;
  static const checkRounded = _check;
  static const chevronLeftRounded = _back;
  static const chevronRight = _chevron;
  static const cleaningServicesOutlined = _clean;
  static const compareOutlined = _compare;
  static const copyOutlined = _copy;
  static const deleteOutline = _trash;
  static const deleteSweepOutlined = _clean;
  static const fingerprint = _fingerprint;
  static const heart = _heart;
  static const homeOutlined = _home;
  static const imageOutlined = _image;
  static const infoOutline = _info;
  static const layersOutlined = _layers;
  static const lockOpen = _lockOpen;
  static const lockOutline = _lock;
  static const moreHoriz = _more;
  static const pauseRounded = _pause;
  static const phoneIphone = _phone;
  static const photoLibraryOutlined = _images;
  static const photoOutlined = _image;
  static const pieChartOutline = _pie;
  static const playArrowRounded = _play;
  static const refreshRounded = _refresh;
  static const filter = _filter;
  static const notificationsOutlined = _bell;
  static const schedule = _clock;
  static const screenshotOutlined = _screenshot;
  static const search = _search;
  static const settingsOutlined = _settings;
  static const shieldOutlined = _shield;
  static const storageOutlined = _storage;
  static const videocamOutlined = _video;
  static const warningAmberRounded = _warning;
}
