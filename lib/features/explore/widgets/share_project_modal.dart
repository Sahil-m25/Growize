import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:arl_app/core/constants/app_links.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/projects/models/marketplace_project.dart';

/// Which entry-point invoked the share modal. Mirrors the v2 mockup's
/// `openShareModal('owner' | 'explore' | 'celebration')` argument and
/// historically controlled the mode label in the header. The
/// redesigned header no longer surfaces a mode chip, but the enum is
/// kept for caller compatibility (Explore detail still passes it).
enum ShareMode { owner, explore, celebration }

/// Visual share-card preview modal with three working share actions:
/// WhatsApp (deep link via `wa.me`), Copy Link (clipboard), and More
/// Options (OS native share sheet via `share_plus`). On web the OS
/// share sheet falls back to copy-to-clipboard.
class ShareProjectModal extends StatefulWidget {
  final MarketplaceProject project;
  final String? heroImageUrl;
  final String? growingTech;
  final String? yieldLabel;
  final String? cropLabel;
  final String? tierLabel;
  final ShareMode mode;
  final String sharerName;

  const ShareProjectModal({
    required this.project,
    this.heroImageUrl,
    this.growingTech,
    this.yieldLabel,
    this.cropLabel,
    this.tierLabel,
    this.mode = ShareMode.owner,
    this.sharerName = 'A Growize investor',
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required MarketplaceProject project,
    String? heroImageUrl,
    String? growingTech,
    String? yieldLabel,
    String? cropLabel,
    String? tierLabel,
    ShareMode mode = ShareMode.owner,
    String sharerName = 'A Growize investor',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareProjectModal(
        project: project,
        heroImageUrl: heroImageUrl,
        growingTech: growingTech,
        yieldLabel: yieldLabel,
        cropLabel: cropLabel,
        tierLabel: tierLabel,
        mode: mode,
        sharerName: sharerName,
      ),
    );
  }

  @override
  State<ShareProjectModal> createState() => _ShareProjectModalState();
}

class _ShareProjectModalState extends State<ShareProjectModal> {
  late final TextEditingController _captionCtl;

  /// Warm-stone modal chrome — deeper than cream so the preview card
  /// reads as the focal object. Picked deliberately to stay in the
  /// brand family (sand-adjacent) without being pure white or pure
  /// cream — both of which made the card blend in.
  static const Color _modalSurface = Color(0xFFF2F1E8);

  @override
  void initState() {
    super.initState();
    _captionCtl = TextEditingController();
  }

  @override
  void dispose() {
    _captionCtl.dispose();
    super.dispose();
  }

  /// Public URL pointing at the marketplace project detail page.
  String get _publicUrl => publicProjectShareUrl(widget.project.id);

  /// Compose the share message. The investor's optional personal note
  /// is prepended; the auto-generated lines describe the project and
  /// drop the public URL plus the sharer's name.
  String _composeMessage() {
    final caption = _captionCtl.text.trim();
    final projectName = widget.project.name;
    final sharer = widget.sharerName;
    final buf = StringBuffer()
      ..writeln('I came across this amazing project — $projectName — '
          'on Growize and thought you might find it interesting.')
      ..writeln();
    if (caption.isNotEmpty) {
      buf
        ..writeln(caption)
        ..writeln();
    }
    buf
      ..writeln(_publicUrl)
      ..writeln()
      ..write('— $sharer');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.92,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _modalSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _dragHandle(),
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _sharePreviewCard()),
                      const SizedBox(height: 16),
                      _captionField(),
                    ],
                  ),
                ),
              ),
              _shareButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Drag handle ──────────────────────────────────────────────────
  // Material-standard pill so the modal feels native and grabable.
  Widget _dragHandle() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: ArlColors.sand,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  // Small share icon + "Share this project" title pinned left, close
  // button right. No divider — the modal surface contrast already
  // separates this strip from the card below.
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 6),
      child: Row(
        children: [
          const Icon(
            Icons.share_outlined,
            size: 16,
            color: ArlColors.primary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Share this project',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: ArlColors.muted, size: 20),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Polished portrait preview card ────────────────────────────────
  // Story-card aesthetic — 280x420 with a 2px gold border, strong
  // shadow, hero image on top 55% and a cream body with hierarchy:
  //
  //   Name (19pt SemiBold charcoal)
  //   Location row (icon + 11pt muted)
  //   Thin sand divider (60% width, left-aligned)
  //   Three stat blocks with accent/gold icons
  //   Gold annual-return pill (the value-prop hook)
  //   Cream→sand gradient bottom strip with growize wordmark + leaf
  Widget _sharePreviewCard() {
    const cardW = 280.0;
    const cardH = 420.0;
    const heroH = 231.0; // 55% of card
    final hero = widget.heroImageUrl ?? widget.project.marketplaceImage;
    final tierLabel =
        (widget.tierLabel ?? widget.project.tier).toUpperCase();
    final totalUnits = widget.project.totalUnits;
    final area = widget.project.acreageAcres;
    final returnPct = widget.project.expectedAnnualReturnPct;

    final unitsStr = totalUnits > 0 ? '$totalUnits' : '—';
    final areaStr = area != null && area > 0
        ? (area % 1 == 0
            ? area.toStringAsFixed(0)
            : area.toStringAsFixed(1))
        : '—';
    final tierDisplay = tierLabel.isNotEmpty ? tierLabel : '—';
    final returnDisplay = returnPct > 0
        ? '+${returnPct % 1 == 0 ? returnPct.toStringAsFixed(0) : returnPct.toStringAsFixed(1)}% Expected Annual Return'
        : 'Expected Annual Return';

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        color: ArlColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ArlColors.gold, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(50, 0, 0, 0),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: heroH,
            width: double.infinity,
            child: hero != null && hero.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: hero,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: ArlColors.sand),
                    errorWidget: (_, __, ___) =>
                        Container(color: ArlColors.sand),
                  )
                : Container(color: ArlColors.sand),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    widget.project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (widget.project.location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 11,
                          color: ArlColors.accent,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            widget.project.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ArlColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  child: Container(
                    height: 1,
                    width: cardW * 0.6 - 18,
                    color: ArlColors.sand,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _statBlock(
                          icon: Icons.dashboard_outlined,
                          iconColor: ArlColors.accent,
                          label: 'TOTAL UNITS',
                          value: unitsStr,
                        ),
                      ),
                      Expanded(
                        child: _statBlock(
                          icon: Icons.grass_outlined,
                          iconColor: ArlColors.accent,
                          label: 'AREA (AC)',
                          value: areaStr,
                        ),
                      ),
                      Expanded(
                        child: _statBlock(
                          icon: Icons.workspace_premium,
                          iconColor: ArlColors.gold,
                          label: 'TIER',
                          value: tierDisplay,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: ArlColors.gold,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: ArlColors.gold.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      returnDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [ArlColors.cream, ArlColors.sand],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'growize',
                        style: TextStyle(
                          color: ArlColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Icon(
                        Icons.eco_outlined,
                        size: 12,
                        color: ArlColors.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One stat block — small accent icon over an uppercase label over
  /// a SemiBold charcoal value. Used in the card's stat row.
  Widget _statBlock({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ArlColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ArlColors.charcoal,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
      ],
    );
  }

  // ── Caption field ─────────────────────────────────────────────────
  Widget _captionField() {
    return TextField(
      controller: _captionCtl,
      maxLines: 3,
      minLines: 2,
      style: const TextStyle(
        fontSize: 13,
        color: ArlColors.charcoal,
        height: 1.35,
      ),
      decoration: InputDecoration(
        hintText: 'Add a personal note (optional)...',
        hintStyle: const TextStyle(
          color: ArlColors.muted,
          fontSize: 13,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ArlColors.sand),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ArlColors.sand),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: ArlColors.primary,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  // ── Share buttons ────────────────────────────────────────────────
  // Three stacked full-width action rows. WhatsApp is the primary
  // (brand green, light shadow, 48px). Copy Link is the secondary
  // (outlined primary, 48px). More Options is the tertiary (muted
  // text, sand border, 44px) — visibly down-weighted.
  Widget _shareButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF25D366).withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => _shareWhatsApp(context),
                icon: const Icon(Icons.chat, size: 16),
                label: const Text(
                  'Share on WhatsApp',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.link, size: 16),
              label: const Text(
                'Copy share link',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: ArlColors.primary,
                side: const BorderSide(color: ArlColors.primary, width: 1.2),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => _shareNative(context),
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text(
                'More sharing options',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: ArlColors.muted,
                side: const BorderSide(color: ArlColors.sand),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Open the universal WhatsApp deep link. We use `https://wa.me/?text=`
  /// (not the `whatsapp://` scheme) so it works on web tabs and on
  /// devices without WhatsApp installed. `LaunchMode.externalApplication`
  /// is essential — without it, web tries to open the link in-frame and
  /// the call silently no-ops.
  Future<void> _shareWhatsApp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _composeMessage();
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(text)}',
    );
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: ArlColors.earth,
            content: Text('Could not open WhatsApp — link copied instead.'),
          ),
        );
        await Clipboard.setData(ClipboardData(text: _publicUrl));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _publicUrl));
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: ArlColors.earth,
          content: Text('Could not open WhatsApp — link copied instead.'),
        ),
      );
    }
  }

  /// Copy the public project URL to the clipboard.
  Future<void> _copyLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _publicUrl));
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: ArlColors.primary,
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Link copied to clipboard')),
          ],
        ),
      ),
    );
  }

  /// Open the OS native share sheet on mobile. On web there is no
  /// system share sheet, so we fall back to copy-to-clipboard.
  Future<void> _shareNative(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _composeMessage();

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: ArlColors.primary,
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Message copied — paste it anywhere')),
            ],
          ),
        ),
      );
      return;
    }

    try {
      await Share.share(
        text,
        subject: 'Growize — ${widget.project.name}',
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: ArlColors.earth,
          content: Text('Could not open share sheet — message copied.'),
        ),
      );
    }
  }
}
