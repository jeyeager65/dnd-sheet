import 'package:flutter/material.dart';

import 'data/character_repository.dart';
import 'data/homebrew_catalog.dart';
import 'data/homebrew_repository.dart';
import 'data/local_official_content.dart';
import 'data/sheet_text_repository.dart';
import 'data/srd_catalog.dart';
import 'screens/character_list_screen.dart';
import 'theme/ledger_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await srdCatalog.init();
  await charactersRepo.init(); // also runs Hive.initFlutter()
  await homebrewRepo.init();
  await sheetTextRepo.init();
  // Merges in a gitignored, machine-local "official content" file if one
  // is present - see data/local_official_content.dart's doc comment. A
  // no-op on any build that doesn't have that file, which is every
  // shared/public build.
  await loadLocalOfficialContent();
  // Homebrew species/classes/backgrounds/subclasses join the catalog, and
  // stay current as they're edited.
  registerHomebrewInCatalog();
  homebrewRepo.afterChange = registerHomebrewInCatalog;
  runApp(const DndSheetApp());
}

class DndSheetApp extends StatelessWidget {
  const DndSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DnD Sheet',
      debugShowCheckedModeBanner: false,
      theme: LedgerTheme.data,
      home: const CharacterListScreen(),
      // On a wide window (the desktop build) every screen keeps a readable
      // width, centered, instead of stretching edge to edge. A phone is
      // narrower than the cap, so nothing changes there.
      builder: (context, child) => ColoredBox(
        color: LedgerColors.paper,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: child,
          ),
        ),
      ),
    );
  }
}
