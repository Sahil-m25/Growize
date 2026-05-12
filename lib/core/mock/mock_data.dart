import 'package:arl_app/features/home/models/portfolio_summary.dart';

// Mock Portfolio Summary Data
final mockPortfolioSummary = PortfolioSummary(
  investorName: 'Sahil Kumar',
  totalInvested: 18300000.0,
  totalReceived: 835000.0,
  pendingAmount: 1200000.0,
  activeUnits: 5,
  nextPayoutAmount: 36400.0,
  nextPayoutDate: DateTime(2026, 4, 15),
  roiPercent: 18.2,
  annualReturns: 835000.0,
);

// Mock Project Model
class MockProject {
  final String id;
  final String name;
  final String cropType;
  final String location;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final int totalUnits;
  final double investedAmount;
  final double progressPercent;
  final int monthOfContract;
  final int totalMonths;
  final String colorHex;
  final String initials;
  final double nextPayoutAmount;
  final DateTime? nextPayoutDate;
  final String cropEmoji;

  MockProject({
    required this.id,
    required this.name,
    required this.cropType,
    required this.location,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.totalUnits,
    required this.investedAmount,
    required this.progressPercent,
    required this.monthOfContract,
    required this.totalMonths,
    required this.colorHex,
    required this.initials,
    required this.nextPayoutAmount,
    required this.nextPayoutDate,
    required this.cropEmoji,
  });

  factory MockProject.greenValley() => MockProject(
    id: 'gv',
    name: 'Green Valley Farm',
    cropType: 'Tomatoes',
    location: 'Pune, Maharashtra',
    status: 'operational',
    startDate: DateTime(2021, 3, 1),
    endDate: DateTime(2026, 3, 1),
    totalUnits: 3,
    investedAmount: 8500000.0,
    progressPercent: 30,
    monthOfContract: 18,
    totalMonths: 60,
    colorHex: '#3C5152',
    initials: 'GV',
    nextPayoutAmount: 12400.0,
    nextPayoutDate: DateTime(2026, 4, 15),
    cropEmoji: '🍅',
  );

  factory MockProject.sunriseOrchards() => MockProject(
    id: 'so',
    name: 'Sunrise Orchards',
    cropType: 'Grapes',
    location: 'Nashik, Maharashtra',
    status: 'operational',
    startDate: DateTime(2020, 9, 1),
    endDate: DateTime(2025, 9, 1),
    totalUnits: 2,
    investedAmount: 5000000.0,
    progressPercent: 45,
    monthOfContract: 27,
    totalMonths: 60,
    colorHex: '#5C3D11',
    initials: 'SO',
    nextPayoutAmount: 14200.0,
    nextPayoutDate: DateTime(2026, 4, 20),
    cropEmoji: '🍇',
  );

  factory MockProject.verdantAcres() => MockProject(
    id: 'va',
    name: 'Verdant Acres',
    cropType: 'Mixed Vegetables',
    location: 'Lonavala, Maharashtra',
    status: 'pending',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2031, 1, 1),
    totalUnits: 2,
    investedAmount: 4800000.0,
    progressPercent: 0,
    monthOfContract: 0,
    totalMonths: 60,
    colorHex: '#2D4A5E',
    initials: 'VA',
    nextPayoutAmount: 0.0,
    nextPayoutDate: null,
    cropEmoji: '🥬',
  );
}

// Mock Projects List
final mockProjects = [
  MockProject.greenValley(),
  MockProject.sunriseOrchards(),
  MockProject.verdantAcres(),
];

// Mock Payout Model
class MockPayout {
  final String id;
  final double amount;
  final String projectId;
  final String projectName;
  final String status;
  final DateTime date;
  final String? utrRef;

  MockPayout({
    required this.id,
    required this.amount,
    required this.projectId,
    required this.projectName,
    required this.status,
    required this.date,
    this.utrRef,
  });
}

// Mock Payouts List
final mockPayouts = [
  MockPayout(
    id: 'p1',
    amount: 12400,
    projectId: 'gv',
    projectName: 'Green Valley Farm',
    status: 'processed',
    date: DateTime(2026, 3, 15),
    utrRef: 'UTR20260315001',
  ),
  MockPayout(
    id: 'p2',
    amount: 14200,
    projectId: 'so',
    projectName: 'Sunrise Orchards',
    status: 'processed',
    date: DateTime(2026, 3, 20),
    utrRef: 'UTR20260320001',
  ),
  MockPayout(
    id: 'p3',
    amount: 12400,
    projectId: 'gv',
    projectName: 'Green Valley Farm',
    status: 'processed',
    date: DateTime(2026, 2, 15),
    utrRef: 'UTR20260215001',
  ),
  MockPayout(
    id: 'p4',
    amount: 13800,
    projectId: 'so',
    projectName: 'Sunrise Orchards',
    status: 'processed',
    date: DateTime(2026, 2, 20),
    utrRef: 'UTR20260220001',
  ),
  MockPayout(
    id: 'p5',
    amount: 11800,
    projectId: 'gv',
    projectName: 'Green Valley Farm',
    status: 'processed',
    date: DateTime(2026, 1, 15),
    utrRef: 'UTR20260115001',
  ),
];

// Mock Notification Model — `type` mirrors HTML notif tinting:
//   warning → arl-earth (red/terracotta), e.g. payout pending
//   success → arl-accent (green),         e.g. new photos / gallery
//   payout  → arl-gold,                   e.g. payout credited
//   info    → arl-primary,                e.g. document available
class MockNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final String type;
  final String? cta;
  final String? ctaRoute;

  MockNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.isRead,
    this.type = 'info',
    this.cta,
    this.ctaRoute,
  });
}

// Mock Notifications List — covers all 4 HTML tints
final mockNotifications = [
  MockNotification(
    id: 'n1',
    title: 'Capital Pending Notice',
    body: '₹12L outstanding. Payouts on hold until cleared.',
    timestamp: DateTime(2026, 4, 22),
    isRead: false,
    type: 'warning',
    cta: 'View Project',
    ctaRoute: '/projects',
  ),
  MockNotification(
    id: 'n2',
    title: 'New Photos Available',
    body: 'Fresh photos from Unit 4 showing healthy growth.',
    timestamp: DateTime(2026, 4, 14),
    isRead: false,
    type: 'success',
    cta: 'View Gallery',
    ctaRoute: '/gallery',
  ),
  MockNotification(
    id: 'n3',
    title: 'Payout Credited',
    body: '₹12,400 credited for Unit 4. UTR: UTIB000123456',
    timestamp: DateTime(2026, 4, 15),
    isRead: false,
    type: 'payout',
    cta: 'View Details',
    ctaRoute: '/financials',
  ),
  MockNotification(
    id: 'n4',
    title: 'Document Available',
    body: 'Your Q1 Payout Statement is ready for download.',
    timestamp: DateTime(2026, 4, 10),
    isRead: true,
    type: 'info',
    cta: 'View',
    ctaRoute: '/documents',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Timeline / History events (HTML #activity-timeline-view)
// ─────────────────────────────────────────────────────────────────────────────
class MockTimelineEvent {
  final String id;
  final String type; // 'payout' | 'operational'
  final String projectId; // 'gv' | 'so' | 'va'
  final String title;
  final String subtitle;
  final DateTime date;
  final double? amount; // payout amount (₹)
  final String? utr;

  const MockTimelineEvent({
    required this.id,
    required this.type,
    required this.projectId,
    required this.title,
    required this.subtitle,
    required this.date,
    this.amount,
    this.utr,
  });
}

final mockTimelineEvents = <MockTimelineEvent>[
  // March 2026
  MockTimelineEvent(
    id: 't1',
    type: 'payout',
    projectId: 'gv',
    title: 'Payout Received',
    subtitle: 'Green Valley — Tomato harvest',
    date: DateTime(2026, 3, 15),
    amount: 12400,
    utr: 'UTIB000123456',
  ),
  MockTimelineEvent(
    id: 't2',
    type: 'payout',
    projectId: 'so',
    title: 'Payout Received',
    subtitle: 'Sunrise Orchards — Grape harvest',
    date: DateTime(2026, 3, 20),
    amount: 14200,
    utr: 'HDFC000456789',
  ),
  MockTimelineEvent(
    id: 't3',
    type: 'operational',
    projectId: 'gv',
    title: 'Operational Milestone',
    subtitle:
        'Tomato harvest stage 2 complete. Yield 18% above target — Green Valley.',
    date: DateTime(2026, 3, 10),
  ),
  MockTimelineEvent(
    id: 't4',
    type: 'operational',
    projectId: 'so',
    title: 'Operational Milestone',
    subtitle:
        'Grape canopy management completed. Brix level on track — Sunrise Orchards.',
    date: DateTime(2026, 3, 12),
  ),
  // February 2026
  MockTimelineEvent(
    id: 't5',
    type: 'payout',
    projectId: 'gv',
    title: 'Payout Received',
    subtitle: 'Green Valley — Tomato harvest',
    date: DateTime(2026, 2, 15),
    amount: 12400,
    utr: 'UTIB000112233',
  ),
  MockTimelineEvent(
    id: 't6',
    type: 'payout',
    projectId: 'so',
    title: 'Payout Received',
    subtitle: 'Sunrise Orchards — Grape harvest',
    date: DateTime(2026, 2, 20),
    amount: 13800,
    utr: 'HDFC000334455',
  ),
  MockTimelineEvent(
    id: 't7',
    type: 'operational',
    projectId: 'va',
    title: 'Operational Milestone',
    subtitle:
        'Verdant Acres — Awaiting capital clearance before kickoff.',
    date: DateTime(2026, 2, 8),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Per-project phase milestones (HTML phase cards in projects-{gv|so|va}-view)
// ─────────────────────────────────────────────────────────────────────────────
class MockPhaseMilestone {
  final String label;
  final String date;
  final bool isDone;
  const MockPhaseMilestone({
    required this.label,
    required this.date,
    required this.isDone,
  });
}

const Map<String, List<MockPhaseMilestone>> mockPhaseMilestones = {
  'gv': [
    MockPhaseMilestone(label: 'Soil Testing',         date: 'Jan \'26', isDone: true),
    MockPhaseMilestone(label: 'Irrigation Setup',     date: 'Feb \'26', isDone: true),
    MockPhaseMilestone(label: 'Shade Net Install',    date: 'Mar \'26', isDone: true),
    MockPhaseMilestone(label: 'Canopy Mgmt',          date: 'May \'26', isDone: false),
    MockPhaseMilestone(label: 'Harvest',              date: 'Aug \'26', isDone: false),
  ],
  'so': [
    MockPhaseMilestone(label: 'Pruning',              date: 'Dec \'25', isDone: true),
    MockPhaseMilestone(label: 'Bud Break',            date: 'Feb \'26', isDone: true),
    MockPhaseMilestone(label: 'Canopy Mgmt',          date: 'Mar \'26', isDone: true),
    MockPhaseMilestone(label: 'Veraison',             date: 'Jun \'26', isDone: false),
    MockPhaseMilestone(label: 'Harvest',              date: 'Sep \'26', isDone: false),
  ],
  'va': [
    MockPhaseMilestone(label: 'Capital Clearance',    date: 'Pending',  isDone: false),
    MockPhaseMilestone(label: 'Land Prep',            date: '—',        isDone: false),
    MockPhaseMilestone(label: 'Sowing',               date: '—',        isDone: false),
    MockPhaseMilestone(label: 'Growth',               date: '—',        isDone: false),
    MockPhaseMilestone(label: 'Harvest',              date: '—',        isDone: false),
  ],
};

// Mock Document Model
class MockDocument {
  final String id;
  final String name;
  final String type;

  const MockDocument({
    required this.id,
    required this.name,
    required this.type,
  });
}

// Mock Documents List
final mockDocuments = [
  const MockDocument(
    id: 'd1',
    name: 'Sale Deed - Green Valley Farm',
    type: 'Legal Document',
  ),
  const MockDocument(
    id: 'd2',
    name: 'Investment Agreement',
    type: 'Legal Document',
  ),
  const MockDocument(
    id: 'd3',
    name: 'KYC Confirmation',
    type: 'Verification',
  ),
  const MockDocument(
    id: 'd4',
    name: 'Payout Statement Q1 FY26',
    type: 'Financial Statement',
  ),
  const MockDocument(
    id: 'd5',
    name: 'Payout Statement Q2 FY26',
    type: 'Financial Statement',
  ),
];

// Mock Upcoming Project Model
class MockUpcomingProject {
  final String id;
  final String name;
  final String location;
  final String farmSize;
  final String crop;
  final int totalUnits;
  final int availableUnits;
  final String deadline;
  final double pricePerUnit;
  final double annualReturnRate;

  const MockUpcomingProject({
    required this.id,
    required this.name,
    required this.location,
    required this.farmSize,
    required this.crop,
    required this.totalUnits,
    required this.availableUnits,
    required this.deadline,
    required this.pricePerUnit,
    required this.annualReturnRate,
  });

  factory MockUpcomingProject.greenValleyPhase2() => const MockUpcomingProject(
    id: 'gv2',
    name: 'Green Valley Phase 2',
    location: 'Pune, Maharashtra',
    farmSize: '88 acres',
    crop: 'Tomatoes & Cucumbers',
    totalUnits: 44,
    availableUnits: 34,
    deadline: '30 Jun 2026',
    pricePerUnit: 2500000.0,
    annualReturnRate: 0.195,
  );

  factory MockUpcomingProject.horizonFields() => const MockUpcomingProject(
    id: 'hf',
    name: 'Horizon Fields',
    location: 'Nashik, Maharashtra',
    farmSize: '65 acres',
    crop: 'Pomegranates',
    totalUnits: 32,
    availableUnits: 28,
    deadline: '31 Jul 2026',
    pricePerUnit: 2200000.0,
    annualReturnRate: 0.188,
  );

  factory MockUpcomingProject.sunriseRidge() => const MockUpcomingProject(
    id: 'sr',
    name: 'Sunrise Ridge',
    location: 'Satara, Maharashtra',
    farmSize: '72 acres',
    crop: 'Strawberries',
    totalUnits: 36,
    availableUnits: 30,
    deadline: '15 Aug 2026',
    pricePerUnit: 2800000.0,
    annualReturnRate: 0.202,
  );
}

// Mock Upcoming Projects List
final mockUpcomingProjects = [
  MockUpcomingProject.greenValleyPhase2(),
  MockUpcomingProject.horizonFields(),
  MockUpcomingProject.sunriseRidge(),
];

// Mock Gallery Photo Model
class MockGalleryPhoto {
  final String id;
  final String projectId;
  final String? signedUrl;
  final DateTime uploadedAt;

  MockGalleryPhoto({
    required this.id,
    required this.projectId,
    this.signedUrl,
    required this.uploadedAt,
  });
}

// Mock Gallery Photos List
final mockGalleryPhotos = List.generate(
  9,
  (index) => MockGalleryPhoto(
    id: 'photo_$index',
    projectId: 'gv',
    signedUrl: null,
    uploadedAt: DateTime(2026, 4, 21).subtract(Duration(days: index)),
  ),
);

// Mock Support Ticket Model
class MockSupportTicket {
  final String id;
  final String subject;
  final String status;
  final DateTime createdAt;

  MockSupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.createdAt,
  });
}

// Mock Support Tickets List
final mockSupportTickets = [
  MockSupportTicket(
    id: 'TKT-2847',
    subject: 'Payout not reflected',
    status: 'Resolved',
    createdAt: DateTime(2026, 3, 8),
  ),
  MockSupportTicket(
    id: 'TKT-2756',
    subject: 'Update contact details',
    status: 'In Progress',
    createdAt: DateTime(2026, 2, 28),
  ),
];
