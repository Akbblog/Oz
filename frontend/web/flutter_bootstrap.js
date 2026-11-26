{{flutter_js}}
{{flutter_build_config}}

// Assets (fonts, icons, images) are requested under a path that is different
// for every build: /b/<build id>/assets/... The host maps it back to
// /assets/..., so files can be cached for a long time without any browser
// keeping a stale icon font after a release. The build script replaces the
// placeholder; without it the path still works, it just is not unique.
_flutter.loader.load({
  config: {
    assetBase: '/b/__BUILD_ID__/',
  },
});
