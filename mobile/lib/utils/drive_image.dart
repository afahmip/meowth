// Drive "view" links (https://drive.google.com/file/d/<id>/view) render an
// HTML viewer, not a raw image, so the file id is pulled out and pointed at
// googleusercontent instead, which serves the image directly for
// publicly-shared files.
String? driveImageSrc(String driveUrl) {
  final id = RegExp(r'/d/([^/]+)/').firstMatch(driveUrl)?.group(1);
  return id == null ? null : 'https://lh3.googleusercontent.com/d/$id';
}
