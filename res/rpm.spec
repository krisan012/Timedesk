Name:       timedesk
Version:    1.5.3
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        https://rustdesk.com
Vendor:     timedesk <info@rustdesk.com>
Requires:   gtk3 libxcb libXfixes alsa-lib libva2 gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
The best open-source remote desktop client software, written in Rust.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

%global __python %{__python3}

%install
mkdir -p %{buildroot}/usr/bin/
mkdir -p %{buildroot}/usr/share/timedesk/
mkdir -p %{buildroot}/usr/share/timedesk/files/
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps/
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps/
install -m 755 $HBB/target/release/rustdesk %{buildroot}/usr/bin/timedesk
install $HBB/libsciter-gtk.so %{buildroot}/usr/share/timedesk/libsciter-gtk.so
install $HBB/res/timedesk.service %{buildroot}/usr/share/timedesk/files/
install $HBB/res/128x128@2x.png %{buildroot}/usr/share/icons/hicolor/256x256/apps/timedesk.png
install $HBB/res/scalable.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/timedesk.svg
install $HBB/res/timedesk.desktop %{buildroot}/usr/share/timedesk/files/
install $HBB/res/timedesk-link.desktop %{buildroot}/usr/share/timedesk/files/

%files
/usr/bin/timedesk
/usr/share/timedesk/libsciter-gtk.so
/usr/share/timedesk/files/timedesk.service
/usr/share/icons/hicolor/256x256/apps/timedesk.png
/usr/share/icons/hicolor/scalable/apps/timedesk.svg
/usr/share/timedesk/files/timedesk.desktop
/usr/share/timedesk/files/timedesk-link.desktop
/usr/share/timedesk/files/__pycache__/*

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
    rm /usr/share/applications/timedesk.desktop || true
    rm /usr/share/applications/timedesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
  ;;
esac
