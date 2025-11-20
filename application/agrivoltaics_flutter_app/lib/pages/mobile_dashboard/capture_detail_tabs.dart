import 'package:flutter/material.dart';

class CaptureDetailDualEqualView extends StatefulWidget {
  final String rawUrl;
  final String ndviUrl;
  final String ndreUrl;
  final String overlayUrl;
  final String heatmapUrl;

  const CaptureDetailDualEqualView({
    Key? key,
    required this.rawUrl,
    required this.ndviUrl,
    required this.ndreUrl,
    required this.overlayUrl,
    required this.heatmapUrl,
  }) : super(key: key);

  @override
  _CaptureDetailDualEqualViewState createState() =>
      _CaptureDetailDualEqualViewState();
}

class _CaptureDetailDualEqualViewState extends State<CaptureDetailDualEqualView>
    with SingleTickerProviderStateMixin {
  int selectedTabIndex = 3; // "Overlay" by default
  double blendValue = 0.0;  // 0 = overlay, 1 = heatmap

  String getSelectedUrl() {
    switch (selectedTabIndex) {
      case 0:
        return widget.rawUrl;
      case 1:
        return widget.ndviUrl;
      case 2:
        return widget.ndreUrl;
      case 3:
        return widget.overlayUrl;
      case 4:
        return widget.heatmapUrl;
      default:
        return widget.overlayUrl;
    }
  }

  // A custom pill-style tab bar for the left pane.
  Widget _buildPillTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final List<String> tabs = ["Raw", "NDVI", "NDRE", "Overlay", "Heatmap"];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tabs.length, (index) {
        bool isSelected = index == selectedTabIndex;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedTabIndex = index;
              // Reset blendValue if not on "Overlay" tab.
              if (selectedTabIndex != 3) blendValue = 0.0;
            });
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? primaryColor.withAlpha((0.1 * 255).toInt()) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? primaryColor : Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tabs[index],
                  style: TextStyle(
                    color: isSelected ? primaryColor : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 2,
                    width: 20,
                    color: primaryColor,
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Left pane: Pill tab bar + Card that centers and scales the selected image.
  Widget _buildLeftPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildPillTabBar(context),
        const SizedBox(height: 8),
        Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 784,
              height: 588,
              alignment: Alignment.center,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) {},
                child:InteractiveViewer(
                  panEnabled: true, //disable panning and zoom because it scrolls the whole page as well wtf
                  scaleEnabled: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network( getSelectedUrl(), fit: BoxFit.contain),
                    ],
                  ),
                ),
              )
            ),
          ),
        ),
      ],
    );
  }

  // Right pane: "Overlay Slider" text + Card with a centered, scaled blended image, and slider below.
  Widget _buildRightPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 60, left: 16),
          /*child: Text(
            "Overlay Slider",
            style: Theme.of(context).textTheme.headline6,
          ),*/
        ),
        Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 784,
              height: 588,
              alignment: Alignment.center,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) {},
                child: InteractiveViewer(
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(widget.overlayUrl, fit: BoxFit.contain),
                      Opacity(
                        opacity: blendValue,
                        child: Image.network(widget.heatmapUrl, fit: BoxFit.contain),
                      ),
                    ],
                  ),
                ),
              )
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Text("Overlay"),
                  Expanded(
                      child: Slider(
                        value: blendValue,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: "${(blendValue * 100).round()}%",
                        onChanged: (value) {
                          setState(() {
                            blendValue = value;
                          });
                        },
                      ),
                  ),
                  const Text("Heatmap"),
                ],
              ),
            ) 
          ) 
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two equal-width columns side by side, top-aligned.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLeftPane(context)),
            Expanded(child: _buildRightPane(context)),
          ],
        );
      },
    );
  }
}
