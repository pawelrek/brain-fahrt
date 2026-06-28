/// Canonical domain enums — persisted by Drift (`textEnum`) and consumed by the UI.
/// Names are the stored DB strings: keep them in sync with the handover data model.
library;

/// A bucket is either a sectioned **project** (Improvement/Bug/Issue) or a flat
/// checkable **list**.
enum BucketShape { project, list }

/// Font size preference for the app.
enum FontSize { small, medium, large }

extension FontSizeScale on FontSize {
  double get scale => switch (this) {
        FontSize.small => 0.9,
        FontSize.medium => 1.0,
        FontSize.large => 1.18,
      };
}

/// Item type for project buckets. List items have `type == null`.
enum ItemType { improvement, bug, issue }

extension ItemTypeLabel on ItemType {
  /// Human label shown in chips and section headers.
  String get label => switch (this) {
        ItemType.improvement => 'Improvement',
        ItemType.bug => 'Bug',
        ItemType.issue => 'Issue',
      };

  /// Uppercase plural used by the bucket-detail section headers.
  String get sectionLabel => switch (this) {
        ItemType.improvement => 'IMPROVEMENTS',
        ItemType.bug => 'BUGS',
        ItemType.issue => 'ISSUES',
      };
}
