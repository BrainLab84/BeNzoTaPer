// Datenmodell. Die JSON-Form ("strike-v1") bleibt stabil, damit alte Sicherungen direkt geladen werden können.
import 'util.dart';

const int dataVersion = 1;

/// Eine einzelne Einnahme.
class Intake {
  String t; // "HH:MM" oder ""
  double v;
  int ts; // Millisekunden seit 1970, 0 = unbekannt
  Intake(this.t, this.v, this.ts);
  Map<String, dynamic> toJson() => {'t': t, 'v': v, 'ts': ts};
}

/// Ein Tag im Protokoll.
class DayEntry {
  List<Intake> it;
  double dose;
  double? plan;
  int? stage; // -1 = Stufe nach Planänderung unbekannt
  String? r; // 'ok' | 'lapse'
  DayEntry({List<Intake>? it, this.dose = 0, this.plan, this.stage, this.r}) : it = it ?? [];
  Map<String, dynamic> toJson() => {
        'it': it.map((x) => x.toJson()).toList(),
        'dose': dose,
        if (plan != null) 'plan': plan,
        if (stage != null) 'stage': stage,
        if (r != null) 'r': r,
      };
}

class Note {
  List<String> sx;
  int sym; // 0 = keins, 1..5
  String text;
  Note({List<String>? sx, this.sym = 0, this.text = ''}) : sx = sx ?? [];
  bool get isEmpty => sx.isEmpty && sym == 0 && text.trim().isEmpty;
  Map<String, dynamic> toJson() => {'sx': sx, 'sym': sym, 'text': text};
}

class Tabs {
  List<double> str;
  double split; // 1 = nur ganz, 0.5 = halbierbar, 0.25 = viertelbar
  double? liq; // mg pro ml
  Tabs({required this.str, this.split = 1, this.liq});
  Map<String, dynamic> toJson() => {'str': str, 'split': split, 'liq': liq};
}

class Stock {
  double mg;
  int ts;
  String day;
  Stock(this.mg, this.ts, this.day);
  Map<String, dynamic> toJson() => {'mg': mg, 'ts': ts, 'day': day};
}

class Chg {
  int ts;
  String d;
  String t;
  Chg(this.ts, this.d, this.t);
  Map<String, dynamic> toJson() => {'ts': ts, 'd': d, 't': t};
}

/// Plan-Entwurf, der vorgemerkt oder übernommen werden soll.
class PlanOverride {
  List<double> plan;
  List<int> days;
  int stage;
  String name;
  String unit;
  PlanOverride(this.plan, this.days, this.stage, this.name, this.unit);
  Map<String, dynamic> toJson() => {'plan': plan, 'days': days, 'stage': stage, 'name': name, 'unit': unit};
}

/// Vorgemerkte Änderung (48 Stunden Bedenkzeit).
class Pend {
  String kind; // 'left' | 'plan'
  String why;
  String txt;
  int at;
  int base;
  int? stage; // left
  int? nd; // left
  String? next; // left
  PlanOverride? o; // plan
  Pend({
    required this.kind,
    required this.why,
    required this.txt,
    this.at = 0,
    this.base = 0,
    this.stage,
    this.nd,
    this.next,
    this.o,
  });
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'why': why,
        'txt': txt,
        'at': at,
        'base': base,
        if (stage != null) 'stage': stage,
        if (nd != null) 'nd': nd,
        if (next != null) 'next': next,
        if (o != null) 'o': o!.toJson(),
      };
}

/// Planverlauf: ab [tag] galt Stufe [stufe] mit [dosis] (bis zum nächsten Eintrag). Wird bei jedem echten
/// Dosiswechsel festgehalten, damit vergangene Tage (auch gehaltene) ihre damalige Dosis behalten.
class PlanAb {
  final String tag;
  final int stufe;
  final double dosis;
  const PlanAb(this.tag, this.stufe, this.dosis);
  List<Object> toJson() => [tag, stufe, dosis];
}

class TaperState {
  String name;
  String unit;
  double? step; // mg pro Stufe beim Berechnen (nur zur Anzeige im Rechner)
  double? min; // kleinste Teilung
  int target; // Standard-Tage pro Stufe (JSON-Name "target")
  List<double> plan;
  List<int>? days;
  int stage;
  String? stageStart;
  String? adv;
  String? t0;
  bool hold;
  String? holdSince;
  String? holdUntil;
  String? frz;
  String? frzFloor;
  Set<String> unk;
  Map<String, DayEntry> log;
  Map<String, Note> notes;
  Set<String> good;
  Tabs? tabs;
  Stock? stock;
  int sosN;
  String? pin;
  List<Chg> chg;

  /// Planverlauf (ältester zuerst). Fehlt in Ständen vor v0.2.2.
  List<PlanAb> ph;
  Pend? pend;
  String? wkSeen;

  /// Name der Person (freiwillig, für die Begrüßung). Nicht verwechseln mit [name] = Medikament.
  String? person;

  TaperState({
    required this.name,
    required this.unit,
    this.step,
    this.min,
    required this.target,
    required this.plan,
    this.days,
    this.stage = 0,
    this.stageStart,
    this.adv,
    this.t0,
    this.hold = false,
    this.holdSince,
    this.holdUntil,
    this.frz,
    this.frzFloor,
    Set<String>? unk,
    Map<String, DayEntry>? log,
    Map<String, Note>? notes,
    Set<String>? good,
    this.tabs,
    this.stock,
    this.sosN = 0,
    this.pin,
    List<Chg>? chg,
    List<PlanAb>? ph,
    this.pend,
    this.wkSeen,
    this.person,
  })  : unk = unk ?? {},
        log = log ?? {},
        notes = notes ?? {},
        good = good ?? {},
        chg = chg ?? [],
        ph = ph ?? [];

  Map<String, dynamic> toJson() => {
        'v': dataVersion,
        'name': name,
        'unit': unit,
        'step': step,
        'min': min,
        'target': target,
        'plan': plan,
        'days': days,
        'stage': stage,
        'stageStart': stageStart,
        'adv': adv,
        't0': t0,
        'hold': hold,
        'holdSince': holdSince,
        'holdUntil': holdUntil,
        'frz': frz,
        'frzFloor': frzFloor,
        'unk': {for (final k in unk) k: 1},
        'log': {for (final e in log.entries) e.key: e.value.toJson()},
        'notes': {for (final e in notes.entries) e.key: e.value.toJson()},
        'good': {for (final k in good) k: 1},
        'tabs': tabs?.toJson(),
        'stock': stock?.toJson(),
        'sosN': sosN,
        'pin': pin,
        'chg': chg.map((c) => c.toJson()).toList(),
        if (ph.isNotEmpty) 'ph': [for (final x in ph) x.toJson()],
        'pend': pend?.toJson(),
        'wkSeen': wkSeen,
        if (person != null) 'person': person,
      };

  // ===== Laden / Prüfen =====

  /// Prüft eine Sicherung und füllt fehlende Felder auf.
  /// Gibt `null` zurück, wenn der Plan kaputt ist. Alte Felder werden ignoriert.
  static TaperState? fromJson(Object? o) {
    if (o is! Map) return null;
    final planRaw = o['plan'];
    final logRaw = o['log'];
    if (planRaw is! List || planRaw.isEmpty) return null;
    if (logRaw is! Map) return null;
    final plan = <double>[];
    for (final x in planRaw) {
      final n = _num(x);
      if (n == null || !n.isFinite || n < 0) return null;
      plan.add(n);
    }
    var stage = _int(o['stage']) ?? 0;
    if (!(stage >= 0 && stage < plan.length)) stage = 0;
    final unitRaw = o['unit'];
    final nameRaw = o['name'];
    final tg = _num(o['target']);
    var target = (tg != null && tg >= 1) ? tg.round() : 14;
    List<int>? days;
    final dRaw = o['days'];
    if (dRaw is List && dRaw.length == plan.length) {
      days = dRaw.map((x) {
        final n = _num(x);
        return (n != null && n > 0) ? n.round() : 0;
      }).toList();
    }
    final s = TaperState(
      name: (nameRaw is String && nameRaw.trim().isNotEmpty) ? nameRaw : 'Medikament',
      unit: (unitRaw is String && unitRaw.trim().isNotEmpty) ? unitRaw : 'mg',
      step: _num(o['step']),
      min: _num(o['min']),
      target: target,
      plan: plan,
      days: days,
      stage: stage,
      stageStart: isDateKey(o['stageStart']) ? o['stageStart'] as String : null,
      adv: isDateKey(o['adv']) ? o['adv'] as String : null,
      t0: isDateKey(o['t0']) ? o['t0'] as String : null,
      hold: o['hold'] == true,
      holdSince: isDateKey(o['holdSince']) ? o['holdSince'] as String : null,
      holdUntil: isDateKey(o['holdUntil']) ? o['holdUntil'] as String : null,
      frz: isDateKey(o['frz']) ? o['frz'] as String : null,
      frzFloor: isDateKey(o['frzFloor']) ? o['frzFloor'] as String : null,
      sosN: _int(o['sosN']) ?? 0,
      pin: o['pin'] is String && (o['pin'] as String).isNotEmpty ? o['pin'] as String : null,
      wkSeen: isDateKey(o['wkSeen']) ? o['wkSeen'] as String : null,
      person:
          o['person'] is String && (o['person'] as String).trim().isNotEmpty ? (o['person'] as String).trim() : null,
    );
    // Protokoll
    for (final e in logRaw.entries) {
      final k = e.key;
      final v = e.value;
      if (k is! String || !isDateKey(k) || v is! Map) continue;
      final its = <Intake>[];
      final itRaw = v['it'];
      if (itRaw is List) {
        for (final x in itRaw) {
          if (x is! Map) continue;
          final val = _num(x['v']);
          if (val == null) continue;
          its.add(Intake(x['t'] is String ? x['t'] as String : '', val, _int(x['ts']) ?? 0));
        }
      }
      s.log[k] = DayEntry(
        it: its,
        dose: _num(v['dose']) ?? 0,
        plan: _num(v['plan']),
        stage: _int(v['stage']),
        r: v['r'] is String && (v['r'] as String).isNotEmpty ? v['r'] as String : null,
      );
    }
    final notes = o['notes'];
    if (notes is Map) {
      for (final e in notes.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) continue;
        final sx = v['sx'] is List ? (v['sx'] as List).whereType<String>().toList() : <String>[];
        s.notes[e.key as String] = Note(
          sx: sx,
          sym: _int(v['sym']) ?? 0,
          text: v['text'] is String ? v['text'] as String : '',
        );
      }
    }
    final unk = o['unk'];
    if (unk is Map) {
      for (final e in unk.entries) {
        if (e.key is String && e.value != null && e.value != 0 && e.value != false) {
          s.unk.add(e.key as String);
        }
      }
    }
    final good = o['good'];
    if (good is Map) {
      for (final e in good.entries) {
        if (e.key is String && e.value != null && e.value != 0 && e.value != false) {
          s.good.add(e.key as String);
        }
      }
    }
    final tabs = o['tabs'];
    if (tabs is Map) {
      final str = (tabs['str'] is List)
          ? (tabs['str'] as List).map(_num).whereType<double>().where((x) => x > 0).toList()
          : <double>[];
      final sp = _num(tabs['split']);
      final lq = _num(tabs['liq']);
      s.tabs = Tabs(
        str: str,
        split: (sp != null && sp > 0) ? sp : 1,
        liq: (lq != null && lq > 0) ? lq : null,
      );
    }
    final st = o['stock'];
    if (st is Map && _num(st['mg']) != null) {
      s.stock = Stock(
        _num(st['mg'])!,
        _int(st['ts']) ?? 0,
        isDateKey(st['day']) ? st['day'] as String : '',
      );
    }
    final chg = o['chg'];
    if (chg is List) {
      for (final c in chg) {
        if (c is! Map) continue;
        s.chg.add(Chg(
            _int(c['ts']) ?? 0, c['d'] is String ? c['d'] as String : '', c['t'] is String ? c['t'] as String : ''));
      }
    }
    final ph = o['ph'];
    if (ph is List) {
      for (final x in ph) {
        if (x is! List || x.length != 3 || !isDateKey(x[0])) continue;
        final st = _int(x[1]), d = _num(x[2]);
        if (st == null || d == null || !d.isFinite || d < 0) continue;
        s.ph.add(PlanAb(x[0] as String, st, d));
      }
      s.ph.sort((a, b) => a.tag.compareTo(b.tag));
    }
    final pe = o['pend'];
    if (pe is Map) s.pend = _pend(pe, plan.length);
    return s;
  }

  static Pend? _pend(Map pe, int planLen) {
    final kind = pe['kind'];
    if (kind != 'left' && kind != 'plan') return null;
    PlanOverride? ov;
    if (kind == 'plan') {
      final o = pe['o'];
      if (o is! Map || o['plan'] is! List || (o['plan'] as List).isEmpty) return null;
      final pl = (o['plan'] as List).map(_num).toList();
      if (pl.any((x) => x == null || !x.isFinite || x < 0)) return null;
      final dRaw = o['days'];
      if (dRaw is! List || dRaw.length != pl.length) return null;
      ov = PlanOverride(
        pl.cast<double>(),
        dRaw.map((x) => (_num(x) ?? 0).round()).toList(),
        (_int(o['stage']) ?? 0).clamp(0, pl.length - 1),
        o['name'] is String ? o['name'] as String : 'Medikament',
        o['unit'] is String ? o['unit'] as String : 'mg',
      );
    }
    return Pend(
      kind: kind as String,
      why: pe['why'] is String ? pe['why'] as String : '',
      txt: pe['txt'] is String ? pe['txt'] as String : '',
      at: _int(pe['at']) ?? 0,
      base: _int(pe['base']) ?? 0,
      stage: _int(pe['stage']),
      nd: _int(pe['nd']),
      next: isDateKey(pe['next']) ? pe['next'] as String : null,
      o: ov,
    );
  }

  static double? _num(Object? x) {
    if (x is num) return x.toDouble();
    if (x is String) return double.tryParse(x.trim());
    return null;
  }

  static int? _int(Object? x) {
    final n = _num(x);
    if (n == null || !n.isFinite) return null;
    return n.round();
  }
}
