import 'dart:io';
import 'package:artofficecraft_mobile/native/gridcraft_bridge.dart';

void main(List<String> args) {
  if(args.length != 1) throw ArgumentError('Expected path to artoffice_core.dll');
  final grid=GridCraftBridge.openLibraryForTesting(args.first);
  final blank=grid.create();
  if(blank.length<100 || blank[0]!=0x50 || blank[1]!=0x4b) {
    throw StateError('GridCraft did not create XLSX');
  }
  final first=grid.editCell(blank,0,'A1','12');
  final second=grid.editCell(first,0,'B1','8');
  final third=grid.editCell(second,0,'C1','=SUM(A1:B1)');
  final report=grid.inspect(third);
  final sheets=report['sheets'] as List<dynamic>;
  final cells=(sheets.first as Map<String,dynamic>)['cells'] as Map<String,dynamic>;
  final result=cells['C1'] as Map<String,dynamic>;
  if(result['input'] != '=SUM(A1:B1)' || result['display'] != '20') {
    throw StateError('GridCraft formula round-trip failed: '+result.toString());
  }
  if(cells['A1']['display'] != '12' || cells['B1']['display'] != '8') {
    throw StateError('GridCraft numeric input lost');
  }
  stdout.writeln('PASS GridCraft create -> edit cells -> SUM = 20 -> reopen XLSX');
  stdout.writeln('XLSX bytes: '+third.length.toString()+', sheet count: '+sheets.length.toString());
}
