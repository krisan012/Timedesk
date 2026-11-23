Name:       timedesk
Version:    1.5.3
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://rustdesk.com
Vendor:     timedesk <info@rustdesk.com>
Requires:   gtk3 libxcb1 libXfixes3 alsa-utils libXtst6 libva2 gstreamer-plugins-base gstreamer-plugin-pipewire
Recommends: libayatana-appindicator3-1 xdotool libdrm.so.2()(64bit) libEGL.so.1()(64bit) libGLESv2.so.2()(64bit)
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)
# libdrmtap is dlopen-ed by the root service only when DRM capture is on, and falls back if it cannot
# load, so its own dependencies (newer glibc, EGL, libdrm) must not become requirements of the package.
%global __requires_exclude_from ^/usr/lib/timedesk/.*$
%global __provides_exclude_from ^/usr/lib/timedesk/.*$

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/timedesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/timedesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/timedesk.service -t "%{buildroot}/usr/share/timedesk/files"
install -Dm 644 $HBB/res/timedesk.desktop -t "%{buildroot}/usr/share/timedesk/files"
install -Dm 644 $HBB/res/timedesk-link.desktop -t "%{buildroot}/usr/share/timedesk/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/timedesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/timedesk.svg"
mkdir -p "%{buildroot}/usr/lib/timedesk"
so=$(find "${DRMTAP_PREBUILT_DIR:-${HBB}/third_party/libdrmtap/build-pkg}" -maxdepth 1 -type f -name 'libdrmtap.so.0.*' 2>/dev/null || true)
if [ -n "$so" ]; then install -Dm 755 "$so" -t "%{buildroot}/usr/lib/timedesk"; ln -s "$(basename "$so")" "%{buildroot}/usr/lib/timedesk/libdrmtap.so.0"; fi

%files
/usr/share/timedesk/*
/usr/lib/timedesk
/usr/share/timedesk/files/timedesk.service
/usr/share/icons/hicolor/256x256/apps/timedesk.png
/usr/share/icons/hicolor/scalable/apps/timedesk.svg
/usr/share/timedesk/files/timedesk.desktop
/usr/share/timedesk/files/timedesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop timedesk || true
  ;;
esac

%post
cp /usr/share/timedesk/files/timedesk.service /etc/systemd/system/timedesk.service
cp /usr/share/timedesk/files/timedesk.desktop /usr/share/applications/
cp /usr/share/timedesk/files/timedesk-link.desktop /usr/share/applications/
ln -sf /usr/share/timedesk/timedesk /usr/bin/timedesk
systemctl daemon-reload
systemctl enable timedesk
systemctl start timedesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop timedesk || true
    systemctl disable timedesk || true
    rm /etc/systemd/system/timedesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/timedesk || true
    rmdir /usr/lib/timedesk || true
    rmdir /usr/local/timedesk || true
    rmdir /usr/share/timedesk || true
    rm /usr/share/applications/timedesk.desktop || true
    rm /usr/share/applications/timedesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/timedesk || true
    rmdir /usr/local/timedesk || true
  ;;
esac
