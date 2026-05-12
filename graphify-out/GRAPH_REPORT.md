# Graph Report - .  (2026-04-23)

## Corpus Check
- Corpus is ~47,894 words - fits in a single context window. You may not need a graph.

## Summary
- 376 nodes · 436 edges · 41 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Explore and Connectivity|Explore and Connectivity]]
- [[_COMMUNITY_Portfolio and Dashboard UI|Portfolio and Dashboard UI]]
- [[_COMMUNITY_Biometric Authentication UI|Biometric Authentication UI]]
- [[_COMMUNITY_App Root and Theme|App Root and Theme]]
- [[_COMMUNITY_Navigation Router|Navigation Router]]
- [[_COMMUNITY_Auth and Login Screens|Auth and Login Screens]]
- [[_COMMUNITY_Activity and Notifications UI|Activity and Notifications UI]]
- [[_COMMUNITY_Project Details UI|Project Details UI]]
- [[_COMMUNITY_Financials and Charts|Financials and Charts]]
- [[_COMMUNITY_Auth Services and Session Management|Auth Services and Session Management]]
- [[_COMMUNITY_Mock Data Factory|Mock Data Factory]]
- [[_COMMUNITY_Project Card UI|Project Card UI]]
- [[_COMMUNITY_Home Dashboard Screen|Home Dashboard Screen]]
- [[_COMMUNITY_Generic Screen Layouts|Generic Screen Layouts]]
- [[_COMMUNITY_User Profile UI|User Profile UI]]
- [[_COMMUNITY_Support and Ticket Creation|Support and Ticket Creation]]
- [[_COMMUNITY_Bank and KYC Profile|Bank and KYC Profile]]
- [[_COMMUNITY_Main Navigation Scaffold|Main Navigation Scaffold]]
- [[_COMMUNITY_Gallery and Media UI|Gallery and Media UI]]
- [[_COMMUNITY_Support Main Screen|Support Main Screen]]
- [[_COMMUNITY_Route Constant Definitions|Route Constant Definitions]]
- [[_COMMUNITY_Android Plugin Registration|Android Plugin Registration]]
- [[_COMMUNITY_Biometric Guard Service|Biometric Guard Service]]
- [[_COMMUNITY_Constants and Environment|Constants and Environment]]
- [[_COMMUNITY_Android Main Activity|Android Main Activity]]
- [[_COMMUNITY_Notification Data Models|Notification Data Models]]
- [[_COMMUNITY_Document Data Models|Document Data Models]]
- [[_COMMUNITY_Payout Data Models|Payout Data Models]]
- [[_COMMUNITY_Gallery Data Models|Gallery Data Models]]
- [[_COMMUNITY_Portfolio Data Models|Portfolio Data Models]]
- [[_COMMUNITY_Investor Unit Models|Investor Unit Models]]
- [[_COMMUNITY_Project Data Models|Project Data Models]]
- [[_COMMUNITY_Project Phase Models|Project Phase Models]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_Graphify Documentation|Graphify Documentation]]
- [[_COMMUNITY_Web Entry Point|Web Entry Point]]
- [[_COMMUNITY_Riverpod State Management|Riverpod State Management]]
- [[_COMMUNITY_Biometric Security Logic|Biometric Security Logic]]
- [[_COMMUNITY_Session State Management|Session State Management]]
- [[_COMMUNITY_Supabase Integration|Supabase Integration]]
- [[_COMMUNITY_Project Identity|Project Identity]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 35 edges
2. `package:arl_app/core/theme/arl_colors.dart` - 23 edges
3. `package:go_router/go_router.dart` - 19 edges
4. `package:flutter_riverpod/flutter_riverpod.dart` - 17 edges
5. `package:arl_app/core/navigation/route_names.dart` - 13 edges
6. `package:arl_app/core/mock/mock_data.dart` - 11 edges
7. `package:intl/intl.dart` - 10 edges
8. `../../core/supabase/supabase_client.dart` - 4 edges
9. `package:supabase_flutter/supabase_flutter.dart` - 3 edges
10. `../supabase/supabase_client.dart` - 3 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Explore and Connectivity"
Cohesion: 0.07
Nodes (24): Connectivity, build, _detailRow, ExploreScreen, _ExploreScreenState, initState, Padding, Scaffold (+16 more)

### Community 1 - "Portfolio and Dashboard UI"
Cohesion: 0.08
Nodes (25): build, PortfolioCard, _PortfolioCardState, SizedBox, Stack, build, Container, ProjectProgressCard (+17 more)

### Community 2 - "Biometric Authentication UI"
Cohesion: 0.07
Nodes (24): BiometricScreen, _BiometricScreenState, build, CircularProgressIndicator, Icon, initState, Scaffold, SizedBox (+16 more)

### Community 3 - "App Root and Theme"
Cohesion: 0.09
Nodes (18): arl_colors.dart, ArlApp, build, build, Container, OfflineBanner, ArlApp, build (+10 more)

### Community 4 - "Navigation Router"
Cohesion: 0.09
Nodes (22): GoRouter, package:arl_app/core/widgets/main_scaffold.dart, package:arl_app/features/activity/activity_screen.dart, package:arl_app/features/auth/auth_screen.dart, package:arl_app/features/documents/documents_screen.dart, package:arl_app/features/exit/exit_screen.dart, package:arl_app/features/explore/explore_screen.dart, package:arl_app/features/financials/financials_screen.dart (+14 more)

### Community 5 - "Auth and Login Screens"
Cohesion: 0.09
Nodes (20): AuthScreen, build, Scaffold, SizedBox, Text, build, Container, _kycField (+12 more)

### Community 6 - "Activity and Notifications UI"
Cohesion: 0.09
Nodes (19): ActivityScreen, build, Container, Scaffold, SizedBox, build, Container, DocumentsScreen (+11 more)

### Community 7 - "Project Details UI"
Cohesion: 0.11
Nodes (16): build, _detailRow, Divider, ProjectDetailScreen, Row, SizedBox, build, Color (+8 more)

### Community 8 - "Financials and Charts"
Cohesion: 0.12
Nodes (16): _barChart, build, _capitalRow, Column, Container, dispose, FinancialsScreen, _FinancialsScreenState (+8 more)

### Community 9 - "Auth Services and Session Management"
Cohesion: 0.12
Nodes (12): saveZohoTokens, SessionManager, ZohoOAuthService, FcmService, _registerToken, ../constants/zoho_constants.dart, ../offline/hive_cache.dart, package:firebase_messaging/firebase_messaging.dart (+4 more)

### Community 10 - "Mock Data Factory"
Cohesion: 0.2
Nodes (9): MockDocument, MockGalleryPhoto, MockNotification, MockPayout, MockProject, MockSupportTicket, MockUpcomingProject, package:arl_app/features/financials/models/payout.dart (+1 more)

### Community 11 - "Project Card UI"
Cohesion: 0.2
Nodes (9): build, Color, GestureDetector, _parseColor, _projectCard, ProjectSelectorScreen, Scaffold, SizedBox (+1 more)

### Community 12 - "Home Dashboard Screen"
Cohesion: 0.2
Nodes (9): build, HomeScreen, Scaffold, SizedBox, Text, package:arl_app/features/home/home_provider.dart, widgets/portfolio_card.dart, widgets/project_progress_card.dart (+1 more)

### Community 13 - "Generic Screen Layouts"
Cohesion: 0.2
Nodes (9): build, Column, Padding, Scaffold, _sectionTitle, SecurityScreen, _SecurityScreenState, SizedBox (+1 more)

### Community 14 - "User Profile UI"
Cohesion: 0.2
Nodes (9): build, GestureDetector, _menuTile, Padding, ProfileScreen, Scaffold, _sectionTitle, SizedBox (+1 more)

### Community 15 - "Support and Ticket Creation"
Cohesion: 0.2
Nodes (9): build, dispose, initState, NewTicketScreen, _NewTicketScreenState, Scaffold, SizedBox, SnackBar (+1 more)

### Community 16 - "Bank and KYC Profile"
Cohesion: 0.22
Nodes (8): BankDetailsScreen, _bankField, build, Container, Scaffold, SizedBox, SnackBar, Text

### Community 17 - "Main Navigation Scaffold"
Cohesion: 0.25
Nodes (7): build, Expanded, _indexForRoute, MainScaffold, _NavItem, Scaffold, SizedBox

### Community 18 - "Gallery and Media UI"
Cohesion: 0.29
Nodes (6): build, Container, GalleryScreen, Scaffold, SizedBox, Text

### Community 19 - "Support Main Screen"
Cohesion: 0.29
Nodes (6): build, GestureDetector, Scaffold, SizedBox, SupportScreen, Text

### Community 20 - "Route Constant Definitions"
Cohesion: 0.5
Nodes (3): locationPath, projectDetailPath, ticketPath

### Community 21 - "Android Plugin Registration"
Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 22 - "Biometric Guard Service"
Cohesion: 0.67
Nodes (2): BiometricGuard, package:local_auth/local_auth.dart

### Community 23 - "Constants and Environment"
Cohesion: 0.67
Nodes (1): package:flutter_dotenv/flutter_dotenv.dart

### Community 24 - "Android Main Activity"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 25 - "Notification Data Models"
Cohesion: 1.0
Nodes (1): ArlNotification

### Community 26 - "Document Data Models"
Cohesion: 1.0
Nodes (1): InvestorDocument

### Community 27 - "Payout Data Models"
Cohesion: 1.0
Nodes (1): Payout

### Community 28 - "Gallery Data Models"
Cohesion: 1.0
Nodes (1): GalleryPhoto

### Community 29 - "Portfolio Data Models"
Cohesion: 1.0
Nodes (1): PortfolioSummary

### Community 30 - "Investor Unit Models"
Cohesion: 1.0
Nodes (1): InvestorUnit

### Community 31 - "Project Data Models"
Cohesion: 1.0
Nodes (1): Project

### Community 32 - "Project Phase Models"
Cohesion: 1.0
Nodes (1): ProjectPhase

### Community 33 - "App Entry Point"
Cohesion: 1.0
Nodes (2): Chrome Browser, lib/main.dart

### Community 34 - "Graphify Documentation"
Cohesion: 1.0
Nodes (2): Graphify Knowledge Graph, Rationale for Graphify Tools

### Community 35 - "Web Entry Point"
Cohesion: 1.0
Nodes (2): flutter_bootstrap.js, web/index.html

### Community 45 - "Riverpod State Management"
Cohesion: 1.0
Nodes (1): flutter_riverpod

### Community 46 - "Biometric Security Logic"
Cohesion: 1.0
Nodes (1): BiometricGuard

### Community 47 - "Session State Management"
Cohesion: 1.0
Nodes (1): SessionManager

### Community 48 - "Supabase Integration"
Cohesion: 1.0
Nodes (1): SupabaseClient

### Community 49 - "Project Identity"
Cohesion: 1.0
Nodes (1): ARL App Project

## Knowledge Gaps
- **284 isolated node(s):** `MainActivity`, `ArlApp`, `build`, `ArlApp`, `main` (+279 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Android Plugin Registration`** (3 nodes): `GeneratedPluginRegistrant.java`, `GeneratedPluginRegistrant`, `.registerWith()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Biometric Guard Service`** (3 nodes): `BiometricGuard`, `biometric_guard.dart`, `package:local_auth/local_auth.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Constants and Environment`** (3 nodes): `supabase_constants.dart`, `zoho_constants.dart`, `package:flutter_dotenv/flutter_dotenv.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Main Activity`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Notification Data Models`** (2 nodes): `ArlNotification`, `notification.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Document Data Models`** (2 nodes): `InvestorDocument`, `document.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Payout Data Models`** (2 nodes): `Payout`, `payout.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Gallery Data Models`** (2 nodes): `GalleryPhoto`, `gallery_photo.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Portfolio Data Models`** (2 nodes): `PortfolioSummary`, `portfolio_summary.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Investor Unit Models`** (2 nodes): `InvestorUnit`, `investor_unit.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Data Models`** (2 nodes): `Project`, `project.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Phase Models`** (2 nodes): `ProjectPhase`, `project_phase.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `App Entry Point`** (2 nodes): `Chrome Browser`, `lib/main.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Graphify Documentation`** (2 nodes): `Graphify Knowledge Graph`, `Rationale for Graphify Tools`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Web Entry Point`** (2 nodes): `flutter_bootstrap.js`, `web/index.html`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Riverpod State Management`** (1 nodes): `flutter_riverpod`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Biometric Security Logic`** (1 nodes): `BiometricGuard`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Session State Management`** (1 nodes): `SessionManager`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Supabase Integration`** (1 nodes): `SupabaseClient`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Project Identity`** (1 nodes): `ARL App Project`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `App Root and Theme` to `Explore and Connectivity`, `Portfolio and Dashboard UI`, `Biometric Authentication UI`, `Navigation Router`, `Auth and Login Screens`, `Activity and Notifications UI`, `Project Details UI`, `Financials and Charts`, `Auth Services and Session Management`, `Project Card UI`, `Home Dashboard Screen`, `Generic Screen Layouts`, `User Profile UI`, `Support and Ticket Creation`, `Bank and KYC Profile`, `Main Navigation Scaffold`, `Gallery and Media UI`, `Support Main Screen`?**
  _High betweenness centrality (0.376) - this node is a cross-community bridge._
- **Why does `package:arl_app/core/theme/arl_colors.dart` connect `Portfolio and Dashboard UI` to `Explore and Connectivity`, `Auth and Login Screens`, `Activity and Notifications UI`, `Project Details UI`, `Financials and Charts`, `Project Card UI`, `Home Dashboard Screen`, `Generic Screen Layouts`, `User Profile UI`, `Support and Ticket Creation`, `Bank and KYC Profile`, `Main Navigation Scaffold`, `Gallery and Media UI`, `Support Main Screen`?**
  _High betweenness centrality (0.111) - this node is a cross-community bridge._
- **Why does `package:flutter_riverpod/flutter_riverpod.dart` connect `Explore and Connectivity` to `App Root and Theme`, `Navigation Router`, `Project Details UI`, `Financials and Charts`, `Home Dashboard Screen`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **What connects `MainActivity`, `ArlApp`, `build` to the rest of the system?**
  _284 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Explore and Connectivity` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Portfolio and Dashboard UI` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `Biometric Authentication UI` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._