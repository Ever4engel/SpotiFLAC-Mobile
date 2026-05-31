import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/cross_extension_share_service.dart';
import 'package:spotiflac_android/services/share_intent_service.dart';

class CrossExtensionShareSheet extends StatefulWidget {
  final String name;
  final String artists;
  final String type;
  final String sourceExtensionId;

  const CrossExtensionShareSheet({
    super.key,
    required this.name,
    required this.artists,
    required this.type,
    required this.sourceExtensionId,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required String artists,
    required String type,
    required String sourceExtensionId,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => CrossExtensionShareSheet(
        name: name,
        artists: artists,
        type: type,
        sourceExtensionId: sourceExtensionId,
      ),
    );
  }

  @override
  State<CrossExtensionShareSheet> createState() =>
      _CrossExtensionShareSheetState();
}

class _CrossExtensionShareSheetState extends State<CrossExtensionShareSheet> {
  late final Future<List<CrossExtensionShareResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = const CrossExtensionShareService()
        .findAcrossExtensions(
          name: widget.name,
          artists: widget.artists,
          type: widget.type,
          sourceExtensionId: widget.sourceExtensionId,
        )
        .then((results) {
          final sorted = [...results];
          sorted.sort((a, b) {
            if (a.found != b.found) return a.found ? -1 : 1;
            return a.displayName.compareTo(b.displayName);
          });
          return sorted;
        });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                context.l10n.openInOtherServices,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                widget.artists.isNotEmpty
                    ? '${widget.name} - ${widget.artists}'
                    : widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<CrossExtensionShareResult>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final results = snapshot.data ?? const [];
                  if (results.isEmpty) {
                    return SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          context.l10n.shareSheetNoExtensions,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemBuilder: (context, index) {
                      return _CrossExtensionShareTile(result: results[index]);
                    },
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemCount: results.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossExtensionShareTile extends StatelessWidget {
  final CrossExtensionShareResult result;

  const _CrossExtensionShareTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final url = result.found ? result.url : null;
    final hasUrl = url != null && url.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: hasUrl
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          hasUrl ? Icons.link_rounded : Icons.link_off_rounded,
          color: hasUrl
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        result.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        hasUrl
            ? (result.itemName?.isNotEmpty == true ? result.itemName! : url)
            : context.l10n.shareSheetNotFound,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: hasUrl ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: hasUrl
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.l10n.shareSheetCopyLink,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.shareSheetLinkCopied(result.displayName),
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: context.l10n.shareSheetOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                  color: colorScheme.primary,
                  onPressed: () {
                    Navigator.pop(context);
                    ShareIntentService().injectUrl(url);
                  },
                ),
              ],
            )
          : null,
    );
  }
}
