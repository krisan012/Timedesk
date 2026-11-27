import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

// TimeDesk home: the recent peers with the same cards as the Devices tab.
class RecentDevices extends StatefulWidget {
  final VoidCallback? onSeeAll;
  const RecentDevices({Key? key, this.onSeeAll}) : super(key: key);

  @override
  State<RecentDevices> createState() => _RecentDevicesState();
}

class _RecentDevicesState extends State<RecentDevices> {
  String _queried = '';

  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
  }

  void _queryOnlines(List<Peer> peers) {
    final ids = peers.map((p) => p.id).toList();
    final key = ids.join(',');
    if (key.isEmpty || key == _queried) return;
    _queried = key;
    bind.queryOnlines(ids: ids);
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final primary = Theme.of(context).colorScheme.primary;
    return ChangeNotifierProvider.value(
      value: gFFI.recentPeersModel,
      child: Consumer<Peers>(builder: (context, model, _) {
        final peers = model.peers;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _queryOnlines(peers));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(translate('Recent devices').toUpperCase(),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: hint)),
              const Spacer(),
              if (widget.onSeeAll != null)
                InkWell(
                  onTap: widget.onSeeAll,
                  child: Text(translate('See all'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: primary)),
                ),
            ]).marginOnly(bottom: 10),
            Expanded(
              child: peers.isEmpty
                  ? Center(
                      child: Text(translate('No recent devices yet'),
                          style: TextStyle(color: hint)))
                  // Sizes match the Devices tab grid in peers_view.dart.
                  : SingleChildScrollView(
                      child: Obx(() => peerCardUiType.value ==
                              PeerUiType.list
                          ? Column(
                              children: peers
                                  .map((p) => SizedBox(
                                      height: 45,
                                      child: RecentPeerCard(peer: p)))
                                  .toList(),
                            )
                          : Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: peers
                                  .map((p) => SizedBox(
                                      width: 220,
                                      height: peerCardUiType.value ==
                                              PeerUiType.grid
                                          ? 140
                                          : 42,
                                      child: RecentPeerCard(peer: p)))
                                  .toList(),
                            )),
                    ),
            ),
          ],
        );
      }),
    );
  }
}
