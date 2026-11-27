import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/host_password_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/theme_fade.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  // Set by the TimeDesk check-in when Timelapse changed this PC's ID or password.
  var timedeskNotice = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();
  final _permanentPasswordSet = false.obs;
  final _showPermanentPassword = false.obs;
  // TimeDesk Host: the permanent password card turns into the Set password
  // form in place; a separate window took seconds to start.
  final _editingPassword = false.obs;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    if (!isIncomingOnly) {
      return _buildBlock(child: _buildTimedeskHome(context));
    }
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isIncomingOnly
            ? Expanded(child: buildLeftPane(context))
            : buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    // Built directly: a FutureBuilder with a new future each build drew no
    // card for one frame, which made the Host window shrink and regrow.
    final helpCards = Obx(() => buildHelpCards(stateGlobal.updateUrl.value));
    final children = isIncomingOnly
        ? _incomingOnlyChildren(context, helpCards)
        : <Widget>[
            if (!isOutgoingOnly) buildPresetPasswordWarning(),
            Align(
              alignment: Alignment.center,
              child: loadLogo(),
            ).marginOnly(bottom: 6),
            buildTip(context),
            if (!isOutgoingOnly)
              _macGroup(context, [
                buildIDBoard(context),
                _macSeparator(context),
                buildPasswordBoard(context),
              ]),
            if (!isOutgoingOnly) _buildTipText(context),
            helpCards,
          ];
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? null : 236.0,
        color: isIncomingOnly
            ? (Theme.of(context).brightness == Brightness.dark
                ? MyTheme.macWindowDark
                : MyTheme.grayBg)
            : Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            // Bounded and not user-scrollable: while the Host window catches up
            // with taller content, the bottom is clipped instead of overflowing.
            SingleChildScrollView(
              controller: _leftPaneScrollController,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                key: _childKey,
                children: children,
              ),
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  // TimeDesk Host: the client's look in a fixed-width window. Logo and status
  // on top, the address card, the permanent password card when shown, notices.
  List<Widget> _incomingOnlyChildren(BuildContext context, Widget helpCards) {
    _fitHostWindowAfterFrame();
    return [
      _presetPasswordWarning,
      Row(
        children: [
          SizedBox(
            width: 200,
            height: 48,
            child: Align(alignment: Alignment.centerLeft, child: loadLogo()),
          ),
          const Spacer(),
          _buildHostThemeButton(context),
          const SizedBox(width: 8),
          _buildStatusPill(context),
        ],
      ).paddingOnly(left: 12, right: 24, top: 8, bottom: 14),
      _buildAddressCard(context),
      Obx(() {
        _fitHostWindowAfterFrame();
        if (!_showPermanentPassword.value) return const SizedBox.shrink();
        return _hostCard(
            context,
            _editingPassword.value
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(translate('Set permanent password').toUpperCase(),
                          style: _macCaption(context).copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.9)),
                      const SizedBox(height: 10),
                      HostPasswordForm(
                          onDone: () => _editingPassword.value = false),
                    ],
                  ).paddingOnly(left: 12, top: 10, right: 12, bottom: 10)
                : _buildPermanentPasswordRow(context));
      }),
      _buildPermanentPasswordToggle(context),
      helpCards.paddingSymmetric(horizontal: 10),
      // Hidden: the pill shows the status, this keeps it polled.
      Offstage(
        child: OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  // Fit the window to the content after a build, not only after the timed
  // calls elsewhere, which can miss a change and clip the bottom card.
  void _fitHostWindowAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isInHomePage()) _updateWindowSize();
    });
  }

  // TimeDesk Host has no Settings window: the theme cycles from the header,
  // Light -> Dark -> System like the client's nav rail.
  Widget _buildHostThemeButton(BuildContext context) {
    return Obx(() {
      final mode = _themeMode.value;
      final next = mode == ThemeMode.light
          ? ThemeMode.dark
          : mode == ThemeMode.dark
              ? ThemeMode.system
              : ThemeMode.light;
      return KeyedSubtree(
        key: _themeToggleKey,
        child: _boxIconButton(context,
            icon: mode == ThemeMode.light
                ? Icons.light_mode_outlined
                : mode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.brightness_auto_outlined,
            tooltip: mode == ThemeMode.light
                ? 'Light'
                : mode == ThemeMode.dark
                    ? 'Dark'
                    : 'Follow System', onTap: () async {
          _themeMode.value = next;
          final box =
              _themeToggleKey.currentContext?.findRenderObject() as RenderBox?;
          await changeThemeWithFade(() => MyTheme.changeDarkMode(next),
              origin: box?.localToGlobal(box.size.center(Offset.zero)));
        }),
      );
    });
  }

  Widget _hostCard(BuildContext context, Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: dark ? MyTheme.macGroupDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.45 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  // A rounded, hairline-bordered group box, like the grouped rows in the
  // macOS sidebar and System Settings.
  Widget _macGroup(BuildContext context, List<Widget> children) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: dark ? MyTheme.macGroupDark : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: dark ? MyTheme.macSeparatorDark : const Color(0xFFE3E3E8),
            width: 0.5),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _macSeparator(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 12),
      color: dark ? MyTheme.macSeparatorDark : MyTheme.macSeparatorLight,
    );
  }

  TextStyle _macCaption(BuildContext context) => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF98989D)
            : MyTheme.macSecondaryLabel,
      );

  Widget _macIconButton(BuildContext context,
      {required IconData icon,
      required String tooltip,
      required VoidCallback? onTap}) {
    final hover = false.obs;
    final base = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF98989D)
        : MyTheme.macSecondaryLabel;
    return Tooltip(
      message: translate(tooltip),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        onHover: (v) => hover.value = v,
        child: Obx(() => Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: hover.value
                    ? base.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(icon,
                  size: 15,
                  color: hover.value
                      ? Theme.of(context).textTheme.titleLarge?.color
                      : base),
            )),
      ),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(translate("ID"), style: _macCaption(context)),
              const Spacer(),
              _macIconButton(context,
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: model.serverId.text));
                    showToast(translate("Copied"));
                  }),
              // TimeDesk Host has no settings window and a fixed ID.
              if (!bind.isIncomingOnly()) buildPopupMenu(context),
            ],
          ),
          GestureDetector(
            onDoubleTap: () {
              Clipboard.setData(ClipboardData(text: model.serverId.text));
              showToast(translate("Copied"));
            },
            child: TextFormField(
              controller: model.serverId,
              readOnly: true,
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.only(top: 2, bottom: 2),
              ),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ).workaroundFreezeLinuxMint(),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    return _macIconButton(context,
        icon: Icons.more_horiz,
        tooltip: 'Settings',
        onTap: DesktopTabPage.onAddSetting);
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AutoSizeText(
                  translate("One-time Password"),
                  style: _macCaption(context),
                  maxLines: 1,
                ),
              ),
              if (showOneTime)
                _macIconButton(context,
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy',
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: model.serverPasswd.text));
                      showToast(translate("Copied"));
                    }),
              if (showOneTime)
                _macIconButton(context,
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh Password',
                    onTap: () => bind.mainUpdateTemporaryPassword()),
              if (!bind.isDisableSettings() && !bind.isIncomingOnly())
                _macIconButton(context,
                    icon: Icons.edit_outlined,
                    tooltip: 'Change Password',
                    onTap: () => DesktopSettingPage.switch2page(
                        SettingsTabKey.safety)),
            ],
          ),
          GestureDetector(
            onDoubleTap: () {
              if (showOneTime) {
                Clipboard.setData(ClipboardData(text: model.serverPasswd.text));
                showToast(translate("Copied"));
              }
            },
            child: TextFormField(
              controller: model.serverPasswd,
              readOnly: true,
              decoration: InputDecoration(
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.only(top: 4, bottom: 2),
              ),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2),
            ).workaroundFreezeLinuxMint(),
          ),
        ],
      ),
    );
  }

  // TimeDesk Host: the permanent password is never shown, only whether one
  // is set, so it is not mistaken for the one-time password above.
  Widget _buildPermanentPasswordRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AutoSizeText(
                  translate("Permanent Password").toUpperCase(),
                  style: _macCaption(context).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9),
                  maxLines: 1,
                ),
              ),
              if (!bind.isDisableSettings())
                _boxIconButton(context,
                    icon: Icons.edit_outlined,
                    tooltip: 'Set permanent password',
                    onTap: () => _editingPassword.value = true),
            ],
          ),
          Obx(() => Text(
                _permanentPasswordSet.value
                    ? '●●●●●●●●  ${translate("Set")}'
                    : translate("Not set"),
                style: _permanentPasswordSet.value
                    ? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)
                    : _macCaption(context).copyWith(fontSize: 13),
              ).marginOnly(top: 4)),
        ],
      ),
    );
  }

  Widget _buildPermanentPasswordToggle(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          _showPermanentPassword.toggle();
          Future.delayed(Duration(milliseconds: 300), _updateWindowSize);
        },
        child: Obx(() => Text(
              translate(_showPermanentPassword.value
                  ? "Hide permanent password"
                  : "Show permanent password"),
              style: _macCaption(context)
                  .copyWith(fontSize: 11, fontWeight: FontWeight.w400),
            ).paddingSymmetric(horizontal: 4, vertical: 2)),
      ),
    ).marginOnly(top: 6, right: 24, bottom: 4);
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    if (isOutgoingOnly) {
      return _buildTipText(context);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          translate("Your Desktop"),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildTipText(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 16, 6),
      child: Text(
        translate(isOutgoingOnly ? "outgoing_only_desk_tip" : "desk_tip"),
        overflow: TextOverflow.clip,
        style: _macCaption(context).copyWith(
            fontWeight: FontWeight.w400, fontSize: 11.5, height: 1.35),
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (bind.isIncomingOnly() && timedeskNotice.isNotEmpty) {
      return buildInstallCard("", timedeskNotice, "OK", () async {
        await bind.mainSetOption(key: 'timedesk-notice', value: '');
        setState(() => timedeskNotice = '');
      });
    }
    if (isWindows &&
        !bind.isDisableInstallation() &&
        bind.mainIsInstalled() &&
        !bind.isOutgoingOnly() &&
        !mainGetBoolOptionSync(kOptionStopService) &&
        !bind.mainIsInstalledDaemon(prompt: false)) {
      return buildInstallCard("", "install_daemon_tip", "Install", () async {
        await rustDeskWinManager.closeAllSubWindows();
        await start_service(true);
      });
    }
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          // macOS shows the request prompt only once per app, so later
          // presses would do nothing without opening the settings pane.
          launchUrl(Uri.parse(
              'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      final drmSupported = bind.mainIsInstalled() &&
          bind.mainGetCommonSync(key: 'is-drm-capture-supported') == 'true';
      if (drmSupported && mainGetBoolOptionSync(kOptionAllowDrmCapture)) {
        // DRM capture reaches the session and the login screen: no warning.
      } else if (drmSupported &&
          !isOptionFixed(kOptionAllowDrmCapture) &&
          !bind.isDisableSettings()) {
        final currentIsWayland = bind.mainCurrentIsWayland();
        if (currentIsWayland || bind.mainIsLoginWayland()) {
          LinuxCards.add(buildInstallCard(
              "Warning",
              currentIsWayland ? "wayland-drm-tip" : "login-wayland-drm-tip",
              "Enable", () async {
            await mainSetBoolOption(kOptionAllowDrmCapture, true);
            setState(() {});
          },
              marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
              help: 'Help',
              link: currentIsWayland
                  ? 'https://rustdesk.com/docs/en/client/linux/#x11-required'
                  : 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
        }
      } else if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      final quitButtonText =
          bind.mainGetBuildinOption(key: kOptionQuitButtonText).trim();
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(quitButtonText.isEmpty ? translate('Quit') : quitButtonText),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  // TimeDesk Host: the help card as one slim row instead of a big block.
  Widget _hostBanner(
      String content, String btnText, GestureTapCallback onPressed,
      {VoidCallback? onClose}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? MyTheme.accentDark : MyTheme.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: dark ? MyTheme.macGroupDark : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.45 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        Icon(Icons.shield_outlined, color: accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            translate(content),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _macCaption(context).copyWith(fontSize: 11.5, height: 1.3),
          ),
        ),
        if (btnText.isNotEmpty) ...[
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(translate(btnText)),
          ),
        ],
        if (onClose != null)
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            splashRadius: 14,
            onPressed: onClose,
          ),
      ]),
    );
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return _hostBanner(content, btnText, onPressed,
        onClose: closeButton == true ? closeCard : null);
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      if (bind.isIncomingOnly()) {
        _permanentPasswordSet.value =
            (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
        final notice = await bind.mainGetOption(key: 'timedesk-notice');
        if (notice != timedeskNotice) {
          timedeskNotice = notice;
          setState(() {});
        }
        // Retry a resize Windows ignored, e.g. one sent while a click on the
        // page was being handled as a window drag.
        if (mounted && isInHomePage()) await _updateWindowSize();
      }
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
          loginMethod: call.arguments['loginMethod'] ?? '',
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() async {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      // Width stays fixed: the pane fills the window, so only height follows content.
      imcomingOnlyHomeSize = Size(imcomingOnlyHomeSize.width, size.height);
      // Compare with the real window, not the last size asked for: a resize
      // that did not take effect would otherwise never be retried.
      final want = getIncomingOnlyHomeSize();
      final have = await windowManager.getSize();
      if ((have.height - want.height).abs() > 1 ||
          (have.width - want.width).abs() > 1) {
        await windowManager.setSize(want);
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  // TimeDesk client: nav rail on the left, Connect or Devices on the right.
  final _navIndex = 0.obs;
  // TimeDesk Host: the one-time code starts hidden; clicking it shows or
  // hides it. The client always shows it.
  final _codeRevealed = (!bind.isIncomingOnly()).obs;
  // Built once: it starts a new check, with a spinner, each time it is built.
  late final Widget _presetPasswordWarning = buildPresetPasswordWarning();
  final _themeMode = MyTheme.getThemeModePreference().obs;
  final _themeToggleKey = GlobalKey();

  // Light -> Dark -> System, the same three choices as Settings > Theme.
  Widget _buildThemeToggle(
      Widget Function(IconData, String, VoidCallback) item) {
    return Obx(() {
      final mode = _themeMode.value;
      final next = mode == ThemeMode.light
          ? ThemeMode.dark
          : mode == ThemeMode.dark
              ? ThemeMode.system
              : ThemeMode.light;
      return Tooltip(
        key: _themeToggleKey,
        message: translate(mode == ThemeMode.light
            ? 'Light'
            : mode == ThemeMode.dark
                ? 'Dark'
                : 'Follow System'),
        child: item(
            mode == ThemeMode.light
                ? Icons.light_mode_outlined
                : mode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : Icons.brightness_auto_outlined,
            mode == ThemeMode.light
                ? 'Light'
                : mode == ThemeMode.dark
                    ? 'Dark'
                    : 'System', () async {
          _themeMode.value = next;
          final box =
              _themeToggleKey.currentContext?.findRenderObject() as RenderBox?;
          await changeThemeWithFade(() => MyTheme.changeDarkMode(next),
              origin: box?.localToGlobal(box.size.center(Offset.zero)));
        }),
      );
    });
  }

  Widget _buildTimedeskHome(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNavRail(context),
        Expanded(
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? MyTheme.macWindowDark
                : MyTheme.grayBg,
            // Wide screens: keep the layout centered instead of stretched.
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Obx(() => _navIndex.value == 0
                    ? _buildConnectView(context)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                        child: PeerTabPage(),
                      )),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavRail(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget item(IconData icon, String label, VoidCallback onTap,
        {int? index}) {
      return Obx(() {
        final selected = _navIndex.value == index;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? (dark ? MyTheme.macGroupDark : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected && !dark
                  ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 3,
                          offset: const Offset(0, 1))
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : _macCaption(context).color),
                const SizedBox(height: 3),
                Text(translate(label),
                    style: _macCaption(context).copyWith(
                        fontSize: 10.5,
                        color: selected
                            ? Theme.of(context).textTheme.titleLarge?.color
                            : null)),
              ],
            ),
          ),
        ).marginOnly(bottom: 6);
      });
    }

    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Column(
        children: [
          item(Icons.link_rounded, 'Connect', () => _navIndex.value = 0,
              index: 0),
          item(Icons.desktop_windows_outlined, 'Devices',
              () => _navIndex.value = 1,
              index: 1),
          const Spacer(),
          _buildThemeToggle((icon, label, onTap) => item(icon, label, onTap)),
          if (!bind.isDisableSettings())
            item(Icons.settings_outlined, 'Settings',
                () => DesktopTabPage.onAddSetting()),
        ],
      ),
    );
  }

  Widget _buildConnectView(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(translate('Connect'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!isOutgoingOnly) _buildStatusPill(context),
            ],
          ).paddingOnly(left: 24, top: 20, right: 24, bottom: 12),
          if (!isOutgoingOnly) _presetPasswordWarning,
          if (!isOutgoingOnly) _buildAddressCard(context),
          Expanded(
              child: ConnectionPage(onSeeAll: () => _navIndex.value = 1)),
          Obx(() => buildHelpCards(stateGlobal.updateUrl.value))
              .paddingSymmetric(horizontal: 10),
        ],
      ),
    );
  }

  Widget _boxIconButton(BuildContext context,
      {required IconData icon,
      required String tooltip,
      required VoidCallback? onTap}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: translate(tooltip),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2B3036) : const Color(0xFFE9EBED),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _macCaption(context).color),
        ),
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context) {
    return Obx(() {
      final status = stateGlobal.svcStatus.value;
      final stopped = svcStopped.value;
      final ready = !stopped && status == SvcStatus.ready;
      final text = stopped
          ? 'Service is not running'
          : status == SvcStatus.connecting
              ? 'connecting_status'
              : ready
                  ? 'Ready for connections'
                  : 'not_ready_status';
      final color = ready
          ? Theme.of(context).colorScheme.primary
          : status == SvcStatus.connecting
              ? kColorWarn
              : _macCaption(context).color!;
      final pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(translate(text),
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );
      if (!stopped) return pill;
      return Tooltip(
        message: translate('Start service'),
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => start_service(true),
            child: pill),
      );
    });
  }

  Widget _buildAddressCard(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final caption = _macCaption(context);
    final label = caption.copyWith(
        fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.9);
    const mono = TextStyle(
        fontFamily: 'Cascadia Mono',
        fontFamilyFallback: ['Consolas', 'Courier New'],
        fontWeight: FontWeight.w500);

    return Consumer<ServerModel>(builder: (context, model, _) {
      final showOneTime = model.approveMode != 'click' &&
          model.verificationMethod != kUsePermanentPassword;
      return Container(
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 0),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: BoxDecoration(
          color: dark ? MyTheme.macGroupDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.45 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate("This device's address").toUpperCase(),
                        style: label),
                    const SizedBox(height: 6),
                    Row(children: [
                      Flexible(
                        child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: model.serverId,
                            builder: (_, v, __) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(v.text,
                                    maxLines: 1,
                                    style: mono.copyWith(
                                        fontSize: 28, letterSpacing: 1.5)))),
                      ),
                      const SizedBox(width: 8),
                      _boxIconButton(context,
                          icon: Icons.copy_rounded,
                          tooltip: 'Copy',
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: model.serverId.text));
                            showToast(translate("Copied"));
                          }),
                      if (!bind.isDisableSettings() &&
                          !bind.isIncomingOnly()) ...[
                        const SizedBox(width: 6),
                        _boxIconButton(context,
                            icon: Icons.more_horiz,
                            tooltip: 'Settings',
                            onTap: DesktopTabPage.onAddSetting),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        translate(
                            'Share the address and the code to let someone in.'),
                        style: caption.copyWith(fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
              VerticalDivider(
                  width: 32, color: Theme.of(context).dividerColor),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('One-time code').toUpperCase(),
                        style: label),
                    const SizedBox(height: 6),
                    Row(children: [
                      Flexible(
                        child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: model.serverPasswd,
                            builder: (_, v, __) => Obx(() {
                                  final hidden = showOneTime &&
                                      !_codeRevealed.value;
                                  final canToggle =
                                      showOneTime && bind.isIncomingOnly();
                                  return Tooltip(
                                    message: canToggle
                                        ? translate(hidden
                                            ? 'Click to show'
                                            : 'Click to hide')
                                        : '',
                                    child: MouseRegion(
                                      cursor: canToggle
                                          ? SystemMouseCursors.click
                                          : MouseCursor.defer,
                                      child: GestureDetector(
                                        onTap: canToggle
                                            ? _codeRevealed.toggle
                                            : null,
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                                !showOneTime
                                                    ? '-'
                                                    : hidden
                                                        ? '••••••'
                                                        : v.text,
                                                maxLines: 1,
                                                style: mono.copyWith(
                                                    fontSize: 20,
                                                    letterSpacing:
                                                        hidden ? 2 : null,
                                                    color: hidden
                                                        ? _macCaption(context)
                                                            .color
                                                        : dark
                                                            ? const Color(
                                                                0xFFF26A6E)
                                                            : primary))),
                                      ),
                                    ),
                                  );
                                })),
                      ),
                      const SizedBox(width: 8),
                      if (showOneTime)
                        _boxIconButton(context,
                            icon: Icons.copy_rounded,
                            tooltip: 'Copy',
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }),
                      if (showOneTime) const SizedBox(width: 6),
                      if (showOneTime)
                        _boxIconButton(context,
                            icon: Icons.refresh_rounded,
                            tooltip: 'Refresh Password',
                            onTap: () => bind.mainUpdateTemporaryPassword()),
                    ]),
                    const SizedBox(height: 4),
                    Obx(() => Text(
                        translate(showOneTime && !_codeRevealed.value
                            ? 'Click the code to show it.'
                            : 'Changes after each session.'),
                        style: caption.copyWith(fontWeight: FontWeight.w400))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}

// TimeDesk client: below this the Connect page starts to crop.
const kTimedeskMinWindowSize = Size(820, 620);
const kTimedeskDefaultWindowSize = Size(1000, 720);
// Above this the window can stretch across two screens.
const kTimedeskMaxWindowSize = Size(1400, 1000);

/// First start opens at the default size, centered. Later starts keep the
/// saved size, clamped between the minimum and the maximum.
Future<void> fitTimedeskMainWindow(bool restored) async {
  await windowManager.setMinimumSize(kTimedeskMinWindowSize);
  await windowManager.setMaximumSize(kTimedeskMaxWindowSize);
  // Also blocks Win+Up and snapping to the top edge.
  await windowManager.setMaximizable(false);
  windowManager.addListener(_UndoMaximize());
  if (await windowManager.isMaximized()) await windowManager.unmaximize();
  if (!restored) {
    await windowManager.setSize(kTimedeskDefaultWindowSize);
    await windowManager.center();
    return;
  }
  final size = await windowManager.getSize();
  final fitted = Size(
      size.width.clamp(
          kTimedeskMinWindowSize.width, kTimedeskMaxWindowSize.width),
      size.height.clamp(
          kTimedeskMinWindowSize.height, kTimedeskMaxWindowSize.height));
  if (fitted != size) await windowManager.setSize(fitted);
}

// Windows can still maximize through other paths (for example a direct
// SC_MAXIMIZE), which leaves a max-size window parked in a corner.
class _UndoMaximize with WindowListener {
  @override
  void onWindowMaximize() => windowManager.unmaximize();
}
