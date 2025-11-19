import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/site.dart' as models;
import '../../models/zone.dart' as models;
import '../../services/site_service.dart';
import '../../services/zone_service.dart';
import '../create_site_dialog.dart';
import '../edit_site_dialog.dart';
import '../create_zone_dialog.dart';
import '../edit_zone_dialog.dart';

class SiteZoneBreadcrumb extends StatelessWidget {
  const SiteZoneBreadcrumb({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentOrg = appState.selectedOrganization;
    final currentSite = appState.selectedSite;
    final currentZone = appState.selectedZone;

    return InkWell(
      onTap: currentOrg != null ? () => _showSiteZoneSelector(context) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _getBreadcrumbText(currentSite, currentZone),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  String _getBreadcrumbText(models.Site? site, models.Zone? zone) {
    if (site == null) return 'Select Site & Zone';
    if (zone == null) return site.name;
    return '${site.name} › ${zone.name}';
  }

  void _showSiteZoneSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const SiteZoneSelectorSheet(),
    );
  }
}

class SiteZoneSelectorSheet extends StatelessWidget {
  const SiteZoneSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentOrg = appState.selectedOrganization;

    if (currentOrg == null) return const SizedBox.shrink();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Text(
                    'Select Location',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Add Site button
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => CreateSiteDialog(
                          organizationId: currentOrg.id,
                        ),
                      );
                    },
                    tooltip: 'Add Site',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Sites with zones
            Expanded(
              child: StreamBuilder<List<models.Site>>(
                stream: SiteService().getSites(currentOrg.id),
                builder: (context, siteSnapshot) {
                  if (siteSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (siteSnapshot.hasError) {
                    return Center(
                      child: Text('Error: ${siteSnapshot.error}'),
                    );
                  }

                  final sites = siteSnapshot.data ?? [];

                  if (sites.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No sites available'),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: sites.length,
                    itemBuilder: (context, index) {
                      final site = sites[index];
                      return SiteExpansionTile(
                        site: site,
                        orgId: currentOrg.id,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class SiteExpansionTile extends StatefulWidget {
  final models.Site site;
  final String orgId;

  const SiteExpansionTile({
    super.key,
    required this.site,
    required this.orgId,
  });

  @override
  State<SiteExpansionTile> createState() => _SiteExpansionTileState();
}

class _SiteExpansionTileState extends State<SiteExpansionTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isSelected = appState.selectedSite?.id == widget.site.id;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            Icons.business,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          title: Text(
            widget.site.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black,
            ),
          ),
          subtitle: widget.site.address.isNotEmpty
              ? Text(widget.site.address)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => EditSiteDialog(
                      site: widget.site,
                      organizationId: widget.orgId,
                    ),
                  );
                },
                tooltip: 'Edit',
              ),
              // Expand/collapse button
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() => _isExpanded = !_isExpanded);
                },
              ),
            ],
          ),
          onTap: () {
            appState.setSelectedSite(widget.site);
            Navigator.pop(context);
          },
        ),
        if (_isExpanded)
          StreamBuilder<List<models.Zone>>(
            stream: ZoneService().getZones(widget.orgId, widget.site.id),
            builder: (context, zoneSnapshot) {
              if (zoneSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final zones = zoneSnapshot.data ?? [];

              return Column(
                children: [
                  // Add Zone button
                  Padding(
                    padding: const EdgeInsets.only(left: 72, right: 16, top: 8, bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          zones.isEmpty ? 'No zones yet' : 'Zones',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.add, size: 20, color: Theme.of(context).colorScheme.primary),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => CreateZoneDialog(
                                orgId: widget.orgId,
                                siteId: widget.site.id,
                              ),
                            );
                          },
                          tooltip: 'Add Zone',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Zone list
                  ...zones.map((zone) {
                  final isZoneSelected = appState.selectedZone?.id == zone.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                    leading: Icon(
                      Icons.location_on,
                      size: 20,
                      color: isZoneSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[400],
                    ),
                    title: Text(
                      zone.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isZoneSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isZoneSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black87,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => EditZoneDialog(
                            zone: zone,
                            orgId: widget.orgId,
                            siteId: widget.site.id,
                          ),
                        );
                      },
                      tooltip: 'Edit',
                    ),
                    onTap: () {
                      appState.setSelectedSite(widget.site);
                      appState.setSelectedZone(zone);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
                ],
              );
            },
          ),
        const Divider(height: 1),
      ],
    );
  }
}
