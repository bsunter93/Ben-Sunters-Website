// src/engine/constants.ts
var CONFIDENCE = 0.95;
var MIN_PRE = 6;
var MIN_POST = 6;
var GOOD_PRE = 12;
var GOOD_POST = 12;
var MAX_WINDOW = 52;
var PHI_MAX = 0.9;
var PHI_ITERATIONS = 30;
var AR1_LIMIT = 0.8;
var DF_MIN = 2;
var SEASON_PERIOD = {
  weekly: 52,
  monthly: 12
};
var SEASON_HARMONICS = {
  52: 3,
  12: 2
};
var SEASON_LINEUP_MIN = 3;
var PLACEBO_MIN_N = 8;
var PLACEBO_W_MIN = 2;
var PLACEBO_W_CAP = 12;
var PLACEBO_DIVISOR = 19;
var PLACEBO_TILE_MIN_SHARE = 0.5;
var PLACEBO_TOP = 0.1;
var PLACEBO_BULK = 0.25;
var ROBUST_Z = 2;
var ALT_EXPLAINS = 0.5;
var NAIVE_FLOOR = 0.5;
var T_SLOPE = 2;
var T_BEND = 2;
var Z_TAIL = 2;
function TAIL_PERIODS(nPre) {
  return nPre < 12 ? 2 : 3;
}
var DRIFT_SHARE = 0.5;
var NEAR_ZERO_NOISE_MULTIPLE = 1;
var PERCENT_FLOOR_MULTIPLE = 1;
var SMALL_MOVE_SHARE = 0.25;
var MAX_GAP_RUN = 6;
var MIN_CONTROL_PERIODS = 4;
var TOTALS_TOLERANCE = 0.01;
var HEADER_PARSE_SHARE = 0.8;
var DELIMITER_SHARE = 0.9;

// src/engine/dates.ts
var MS_PER_DAY = 864e5;
var DAYS_PER_400_YEARS = 146097;
var MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
var MONTH_NAMES = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december"
];
var TIME_PART = /[T ]\d{1,2}:\d{2}(:\d{2})?(\.\d+)?(Z|[-+]\d{2}:?\d{2})?$/;
var ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
var ISO_SLASH = /^(\d{4})\/(\d{1,2})\/(\d{1,2})$/;
var ISO_MONTH = /^(\d{4})-(\d{2})$/;
var ISO_WEEK = /^(\d{4})-W(\d{2})$/;
var NUMERIC_SLASH_OR_DASH = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})$/;
var MONTH_NAME_YEAR = /^([A-Za-z]{3,9})\.?,?\s+(\d{4})$/;
var MONTH_NAME_DASH_YEAR = /^([A-Za-z]{3,9})-(\d{4}|\d{2})$/;
var MONTH_NAME_DAY_YEAR = /^([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})$/;
var DAY_MONTH_NAME_YEAR = /^(\d{1,2})[\s-]([A-Za-z]{3,9})\.?,?[\s-](\d{4}|\d{2})$/;
var YEAR_MONTH_NAME = /^(\d{4})[\s-]([A-Za-z]{3,9})$/;
function group(match, index) {
  const value = match[index];
  if (value === void 0) {
    throw new RangeError(`Regex group ${index} did not capture.`);
  }
  return value;
}
function int(match, index) {
  return Number.parseInt(group(match, index), 10);
}
function pad(value, width) {
  return String(value).padStart(width, "0");
}
function isLeapYear(year) {
  return year % 4 === 0 && year % 100 !== 0 || year % 400 === 0;
}
function daysInMonth(year, month) {
  const length = MONTH_LENGTHS[month - 1];
  if (!Number.isInteger(month) || length === void 0) {
    throw new RangeError(`Month ${month} is outside 1 to 12.`);
  }
  return month === 2 && isLeapYear(year) ? 29 : length;
}
function isValidCivilDate(year, month, day) {
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return false;
  }
  if (month < 1 || month > 12) {
    return false;
  }
  return day >= 1 && day <= daysInMonth(year, month);
}
function dayNumber(year, month, day) {
  if (year >= 0 && year < 100) {
    return Date.UTC(year + 400, month - 1, day) / MS_PER_DAY - DAYS_PER_400_YEARS;
  }
  return Date.UTC(year, month - 1, day) / MS_PER_DAY;
}
function civilDate(day) {
  const date = new Date(day * MS_PER_DAY);
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate() };
}
function toIsoDate(day) {
  const civil = civilDate(day);
  return `${pad(civil.year, 4)}-${pad(civil.month, 2)}-${pad(civil.day, 2)}`;
}
function isoWeekday(day) {
  return ((day + 3) % 7 + 7) % 7 + 1;
}
function isWeekend(day) {
  return isoWeekday(day) >= 6;
}
function mondayOf(day) {
  return day - (isoWeekday(day) - 1);
}
function isoWeek(day) {
  const thursday = mondayOf(day) + 3;
  const year = civilDate(thursday).year;
  const week = Math.floor((thursday - dayNumber(year, 1, 1)) / 7) + 1;
  return { year, week };
}
function weeksInIsoYear(year) {
  return isoWeek(dayNumber(year, 12, 28)).week;
}
function isoWeekMonday(year, week) {
  if (!Number.isInteger(week) || week < 1 || week > weeksInIsoYear(year)) {
    return null;
  }
  return mondayOf(dayNumber(year, 1, 4)) + 7 * (week - 1);
}
function monthKeyOf(year, month) {
  return year * 12 + month - 1;
}
function monthKey(day) {
  const civil = civilDate(day);
  return monthKeyOf(civil.year, civil.month);
}
function monthKeyStart(key) {
  const year = Math.floor(key / 12);
  const month = key - year * 12 + 1;
  return dayNumber(year, month, 1);
}
function monthStart(day) {
  return monthKeyStart(monthKey(day));
}
function monthFromName(name2) {
  const lower = name2.toLowerCase();
  if (lower === "sept") {
    return 9;
  }
  for (let index = 0; index < MONTH_NAMES.length; index += 1) {
    const full = MONTH_NAMES[index];
    if (full !== void 0 && (lower === full || lower === full.slice(0, 3))) {
      return index + 1;
    }
  }
  return null;
}
function stripTime(cell3) {
  const trimmed = cell3.trim();
  const text = trimmed.replace(TIME_PART, "").trim();
  return { text, stripped: text !== trimmed };
}
function readDate(year, month, day, monthGranularity, twoDigitYear) {
  if (month === null) {
    return null;
  }
  return { year, month, day, monthGranularity, twoDigitYear };
}
function readForms(text) {
  let match = ISO_DATE.exec(text);
  if (match !== null) {
    return readDate(int(match, 1), int(match, 2), int(match, 3), false, false);
  }
  match = ISO_SLASH.exec(text);
  if (match !== null) {
    return readDate(int(match, 1), int(match, 2), int(match, 3), false, false);
  }
  match = ISO_MONTH.exec(text);
  if (match !== null) {
    return readDate(int(match, 1), int(match, 2), 1, true, false);
  }
  match = ISO_WEEK.exec(text);
  if (match !== null) {
    const monday = isoWeekMonday(int(match, 1), int(match, 2));
    if (monday === null) {
      return null;
    }
    const civil = civilDate(monday);
    return readDate(civil.year, civil.month, civil.day, false, false);
  }
  match = NUMERIC_SLASH_OR_DASH.exec(text);
  if (match !== null) {
    const yearText = group(match, 3);
    const twoDigitYear = yearText.length === 2;
    return {
      kind: "slash-candidate",
      first: int(match, 1),
      second: int(match, 2),
      year: twoDigitYear ? 2e3 + int(match, 3) : int(match, 3),
      twoDigitYear,
      strippedTime: false
    };
  }
  match = MONTH_NAME_YEAR.exec(text);
  if (match !== null) {
    return readDate(int(match, 2), monthFromName(group(match, 1)), 1, true, false);
  }
  match = MONTH_NAME_DASH_YEAR.exec(text);
  if (match !== null) {
    const twoDigitYear = group(match, 2).length === 2;
    const year = twoDigitYear ? 2e3 + int(match, 2) : int(match, 2);
    return readDate(year, monthFromName(group(match, 1)), 1, true, twoDigitYear);
  }
  match = MONTH_NAME_DAY_YEAR.exec(text);
  if (match !== null) {
    return readDate(int(match, 3), monthFromName(group(match, 1)), int(match, 2), false, false);
  }
  match = DAY_MONTH_NAME_YEAR.exec(text);
  if (match !== null) {
    const yearText = group(match, 3);
    const twoDigitYear = yearText.length === 2;
    const year = twoDigitYear ? 2e3 + int(match, 3) : int(match, 3);
    return readDate(year, monthFromName(group(match, 2)), int(match, 1), false, twoDigitYear);
  }
  match = YEAR_MONTH_NAME.exec(text);
  if (match !== null) {
    return readDate(int(match, 1), monthFromName(group(match, 2)), 1, true, false);
  }
  return null;
}
function parseDateToken(cell3) {
  const { text, stripped } = stripTime(cell3);
  const read = readForms(text);
  if (read === null) {
    return null;
  }
  if ("kind" in read) {
    return { ...read, strippedTime: stripped };
  }
  if (!isValidCivilDate(read.year, read.month, read.day)) {
    return null;
  }
  return {
    kind: "date",
    day: dayNumber(read.year, read.month, read.day),
    monthGranularity: read.monthGranularity,
    twoDigitYear: read.twoDigitYear,
    strippedTime: stripped
  };
}
function resolveSlashCandidate(candidate, dayFirst) {
  const month = dayFirst ? candidate.second : candidate.first;
  const day = dayFirst ? candidate.first : candidate.second;
  if (!isValidCivilDate(candidate.year, month, day)) {
    return null;
  }
  return {
    kind: "date",
    day: dayNumber(candidate.year, month, day),
    monthGranularity: false,
    twoDigitYear: candidate.twoDigitYear,
    strippedTime: candidate.strippedTime
  };
}

// src/engine/numbers.ts
var MISSING_MARKERS = [
  "",
  "-",
  "--",
  "n/a",
  "na",
  "null",
  "none",
  "nan",
  "#n/a",
  "#value!",
  "#ref!",
  "#div/0!"
];
var EXPONENTS = { K: 3, M: 6, B: 9 };
var UNICODE_MINUS = "\u2212";
var LEADING_SIGN = /^[-+]/;
var SIGN_THEN_CURRENCY = /^([-+]?)\s*([$€£¥])\s*/;
var TRAILING_CURRENCY = /\s*([$€£¥])$/;
var TRAILING_PERCENT = /\s*%$/;
var TRAILING_MAGNITUDE = /\s*([kKmMbB])$/;
var SEPARATOR_BETWEEN_DIGITS = /(\d)[,\s]+(?=\d)/g;
var SPACE_AFTER_SIGN = /^([-+])\s+/;
var NUMBER_BODY = /^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/;
function isMissingMarker(cell3) {
  return MISSING_MARKERS.includes(cell3.trim().toLowerCase());
}
function parseNumberToken(cell3) {
  let s = cell3.trim();
  const unicodeMinus = s.includes(UNICODE_MINUS);
  if (unicodeMinus) {
    s = s.split(UNICODE_MINUS).join("-");
  }
  let negative = false;
  let parenthesized = false;
  if (s.length >= 2 && s.startsWith("(") && s.endsWith(")")) {
    s = s.slice(1, -1).trim();
    negative = true;
    parenthesized = true;
  }
  let trailingMinus = false;
  if (s.length > 1 && s.endsWith("-") && !LEADING_SIGN.test(s)) {
    s = s.slice(0, -1).trim();
    negative = true;
    trailingMinus = true;
  }
  let currencySymbol = null;
  const leading = SIGN_THEN_CURRENCY.exec(s);
  if (leading !== null) {
    currencySymbol = leading[2] ?? null;
    s = (leading[1] ?? "") + s.slice(leading[0].length);
  } else {
    const trailing = TRAILING_CURRENCY.exec(s);
    if (trailing !== null) {
      currencySymbol = trailing[1] ?? null;
      s = s.slice(0, trailing.index);
    }
  }
  let percent = false;
  const pct = TRAILING_PERCENT.exec(s);
  if (pct !== null) {
    percent = true;
    s = s.slice(0, pct.index);
  }
  let magnitude = null;
  const mag = TRAILING_MAGNITUDE.exec(s);
  if (mag !== null) {
    magnitude = (mag[1] ?? "").toUpperCase();
    s = s.slice(0, mag.index);
  }
  const joined = s.replace(SEPARATOR_BETWEEN_DIGITS, "$1");
  const thousands = joined !== s;
  s = joined.replace(SPACE_AFTER_SIGN, "$1");
  if (!NUMBER_BODY.test(s)) {
    return null;
  }
  const decimalPoint = s.includes(".");
  const exponent = magnitude === null ? 0 : EXPONENTS[magnitude];
  let value = scaleByPowerOfTen(s, exponent);
  if (negative) {
    value = -value;
  }
  if (!Number.isFinite(value)) {
    return null;
  }
  if (value === 0) {
    value = 0;
  }
  return {
    value,
    currencySymbol,
    percent,
    magnitude,
    multiplier: Math.pow(10, exponent),
    parenthesized,
    trailingMinus,
    unicodeMinus,
    thousands,
    decimalPoint
  };
}
function scaleByPowerOfTen(body, exponent) {
  if (exponent === 0) {
    return Number(body);
  }
  const split = /^([^eE]+)(?:[eE]([-+]?\d+))?$/.exec(body);
  const mantissa = split?.[1] ?? body;
  const written = split?.[2];
  const total = (written === void 0 ? 0 : Number(written)) + exponent;
  return Number(`${mantissa}e${total}`);
}
function unitByMajority(tokens) {
  let percentCount = 0;
  let currencyCount = 0;
  const symbols = /* @__PURE__ */ new Map();
  for (const token of tokens) {
    if (token.percent) {
      percentCount += 1;
    }
    if (token.currencySymbol !== null) {
      currencyCount += 1;
      symbols.set(token.currencySymbol, (symbols.get(token.currencySymbol) ?? 0) + 1);
    }
  }
  const n = tokens.length;
  if (percentCount * 2 > n) {
    return { unit: "percent", currencySymbol: null };
  }
  if (currencyCount * 2 > n) {
    return { unit: "currency", currencySymbol: mostCommon(symbols) };
  }
  return { unit: "count", currencySymbol: null };
}
function mostCommon(counts) {
  let best = null;
  let bestCount = 0;
  for (const [key, count] of counts) {
    if (count > bestCount) {
      best = key;
      bestCount = count;
    }
  }
  return best;
}

// src/engine/parser.ts
var MIN_LINES = 4;
var MAX_MONTH = 12;
var UNREADABLE_SHARE = 0.2;
var DAYS_PER_WEEK = 7;
var WEEKDAYS_PER_WEEK = 5;
var MONTH_SPACING_MIN = 28;
var MONTH_SPACING_MAX = 31;
var NAMES_IN_MESSAGE = 3;
var COLUMN_SHAPE_MESSAGE = "Paste one column of numbers, or dates and numbers.";
var GENERIC_NAMES = /* @__PURE__ */ new Set(["value", "metric", "count", "amount", "total", "y"]);
var REJOIN_LEFT = /^[-+(]?\s*[$€£¥]?\s*\d{1,3}(,\d{3})*$/;
var REJOIN_RIGHT = /^\d{3}(\.\d+)?\s*[)%kKmMbB]?$/;
var REJOIN_MONTH_DAY = /^([A-Za-z]{3,9})\.?\s+\d{1,2}$/;
var REJOIN_DAY_MONTH = /^\d{1,2}[\s-]([A-Za-z]{3,9})\.?$/;
var REJOIN_YEAR = /^\d{4}$/;
var INTEGER_TEXT = /^\d+$/;
var WHITESPACE = /\s/;
var EMPTY_CELL = { kind: "missing", text: "" };
var DELIMITERS = [
  { delimiter: "	", description: "tabs" },
  { delimiter: ",", description: "commas" },
  { delimiter: ";", description: "semicolons" },
  { delimiter: "|", description: "pipes" },
  { delimiter: null, description: "whitespace" }
];
function parse(text, options = {}) {
  const log = [];
  const lines = readLines(text, log);
  if (lines.length === 0) {
    return failure(log, "empty", "The input is empty.");
  }
  if (lines.length < MIN_LINES) {
    return failure(
      log,
      "too-few-rows",
      `The input has ${plural(lines.length, "line")} and at least ${MIN_LINES} are needed.`
    );
  }
  const table = splitTable(lines, log);
  const grid = classifyTable(table, log);
  const slashError = resolveSlashDates(grid, options, log);
  if (slashError !== null) {
    return { ok: false, errors: [slashError], normalizations: log };
  }
  const { header, rows } = splitHeader(grid, options, log);
  const roles = assignRoles(rows, header, options, log);
  if (!roles.ok) {
    return { ok: false, errors: [roles.error], normalizations: log };
  }
  const cleaned = cleanRows(rows, roles.value, log);
  if (!cleaned.ok) {
    return { ok: false, errors: [cleaned.error], normalizations: log };
  }
  if (cleaned.value.treated.length === 0) {
    return failure(log, "too-few-rows", "No data rows remained after the label rows were dropped.");
  }
  const unit2 = unitByMajority(valueTokens(rows, roles.value.valueCol));
  const built = roles.value.dateCol === null ? buildUndated(cleaned.value) : buildDated(cleaned.value, options, roles.value.summedCol !== null, log);
  let control = built.control;
  const groups = roles.value.groups;
  if (groups !== null) {
    if (!roles.value.treatedFromOptions) {
      record(
        log,
        "treated-group-order",
        "note",
        1,
        () => `Treated group: ${groups.treated}. Comparison group: ${groups.control}. Set treatedLabel to swap them.`
      );
    }
    if (built.treatedOnly > 0 || built.controlOnly > 0) {
      const treatedOnly = built.treatedOnly;
      const controlOnly = built.controlOnly;
      record(
        log,
        "dropped-unmatched-control-dates",
        "warning",
        treatedOnly + controlOnly,
        () => `${plural(treatedOnly, "treated date")} had no comparison value and ${plural(controlOnly, "comparison date")} had no treated value; each is a missing period on the side that lacks it.`
      );
    }
    if (control !== null) {
      const present2 = control.filter((period) => period.value !== null).length;
      if (present2 < MIN_CONTROL_PERIODS) {
        control = null;
        record(
          log,
          "dropped-short-control",
          "warning",
          present2,
          () => `The comparison group has ${plural(present2, "present period")} and at least ${MIN_CONTROL_PERIODS} are needed, so it was dropped.`
        );
      }
    }
  }
  const series = {
    periods: built.periods,
    frequency: built.frequency,
    control,
    groups,
    name: roles.value.name,
    unit: unit2.unit,
    currencySymbol: unit2.currencySymbol,
    normalizations: log,
    gaps: built.gaps
  };
  return { ok: true, series };
}
function failure(log, code, message) {
  return { ok: false, errors: [{ code, message }], normalizations: log };
}
function error(code, message) {
  return { ok: false, error: { code, message } };
}
function record(log, code, severity, count, message) {
  const existing = log.find((entry) => entry.code === code);
  if (existing !== void 0) {
    existing.count += count;
    existing.message = message(existing.count);
    return;
  }
  log.push({ code, message: message(count), count, severity });
}
function plural(count, noun, pluralNoun = `${noun}s`) {
  return `${count} ${count === 1 ? noun : pluralNoun}`;
}
function listNames(names) {
  const shown = names.slice(0, NAMES_IN_MESSAGE).join(", ");
  const rest = names.length - NAMES_IN_MESSAGE;
  return rest > 0 ? `${shown} and ${rest} more` : shown;
}
function labelKey(text) {
  return text.trim().toLowerCase();
}
function columnName(header, col) {
  const name2 = header?.[col]?.trim();
  return name2 !== void 0 && name2.length > 0 ? name2 : `column ${col + 1}`;
}
function cellAt(row, col) {
  return row[col] ?? EMPTY_CELL;
}
function mostCommon2(values) {
  const counts = /* @__PURE__ */ new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  let best = null;
  let bestCount = 0;
  for (const [value, count] of counts) {
    if (count > bestCount || count === bestCount && best !== null && value < best) {
      best = value;
      bestCount = count;
    }
  }
  return best;
}
function isIndexRun(values) {
  const first = values[0];
  if (first === void 0 || first !== 0 && first !== 1) {
    return false;
  }
  return values.every((value, position) => Number.isInteger(value) && value === first + position);
}
function readLines(text, log) {
  const body = (text.startsWith("\uFEFF") ? text.slice(1) : text).replace(/\r\n?/g, "\n").replace(/\s+$/, "");
  if (body.length === 0) {
    return [];
  }
  const all = body.split("\n").map((line) => line.replace(/\s+$/, ""));
  const kept = all.filter((line) => line.length > 0);
  const dropped = all.length - kept.length;
  if (dropped > 0) {
    record(log, "dropped-blank-lines", "note", dropped, (n) => `Dropped ${plural(n, "blank line")}.`);
  }
  return kept;
}
function splitOnChar(line, delimiter) {
  const cells = [];
  let buffer = "";
  let quoted = false;
  let inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line.charAt(i);
    if (inQuotes) {
      if (ch === '"') {
        if (line.charAt(i + 1) === '"') {
          buffer += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        buffer += ch;
      }
    } else if (ch === '"' && buffer.trim() === "") {
      inQuotes = true;
      quoted = true;
      buffer = "";
    } else if (ch === delimiter) {
      cells.push({ text: buffer.trim(), quoted });
      buffer = "";
      quoted = false;
    } else {
      buffer += ch;
    }
  }
  cells.push({ text: buffer.trim(), quoted });
  return cells;
}
function splitOnWhitespace(line) {
  const cells = [];
  let i = 0;
  while (i < line.length) {
    while (i < line.length && WHITESPACE.test(line.charAt(i))) {
      i += 1;
    }
    if (i >= line.length) {
      break;
    }
    if (line.charAt(i) === '"') {
      let buffer = "";
      i += 1;
      while (i < line.length) {
        const ch = line.charAt(i);
        if (ch === '"') {
          if (line.charAt(i + 1) === '"') {
            buffer += '"';
            i += 2;
            continue;
          }
          i += 1;
          break;
        }
        buffer += ch;
        i += 1;
      }
      cells.push({ text: buffer.trim(), quoted: true });
    } else {
      let end = i;
      while (end < line.length && !WHITESPACE.test(line.charAt(end))) {
        end += 1;
      }
      cells.push({ text: line.slice(i, end), quoted: false });
      i = end;
    }
  }
  return cells;
}
function isDateHead(text) {
  const match = REJOIN_MONTH_DAY.exec(text) ?? REJOIN_DAY_MONTH.exec(text);
  return match !== null && match[1] !== void 0 && monthFromName(match[1]) !== null;
}
function rejoinDates(original) {
  const cells = [];
  let merges = 0;
  for (let i = 0; i < original.length; i += 1) {
    const cell3 = original[i];
    const next = original[i + 1];
    if (cell3 === void 0) {
      continue;
    }
    if (next !== void 0 && !cell3.quoted && !next.quoted && REJOIN_YEAR.test(next.text) && isDateHead(cell3.text)) {
      cells.push({ text: `${cell3.text}, ${next.text}`, quoted: false });
      merges += 1;
      i += 1;
    } else {
      cells.push(cell3);
    }
  }
  return { cells, merges };
}
function rejoinLine(original) {
  const cells = [...original];
  let merges = 0;
  let position = -1;
  let i = 0;
  while (i < cells.length - 1) {
    const left = cells[i];
    const right = cells[i + 1];
    if (left !== void 0 && right !== void 0 && !left.quoted && !right.quoted && REJOIN_LEFT.test(left.text) && REJOIN_RIGHT.test(right.text)) {
      cells.splice(i, 2, { text: `${left.text},${right.text}`, quoted: false });
      merges += 1;
      if (position < 0) {
        position = i;
      }
    } else {
      i += 1;
    }
  }
  return { cells, original, merges, position };
}
function isIndexedValueFile(lines) {
  const first = lines[0];
  const second = lines[1];
  const header = first !== void 0 && second !== void 0 && first.merges === 0 && first.original.length === second.original.length;
  const body = header ? lines.slice(1) : lines;
  const sample = body[0];
  if (sample === void 0) {
    return false;
  }
  const leftParts = [];
  for (const line of body) {
    const left = line.original[line.position];
    if (line.merges !== 1 || line.position !== sample.position || line.original.length !== sample.original.length || left === void 0 || !INTEGER_TEXT.test(left.text)) {
      return false;
    }
    leftParts.push(Number.parseInt(left.text, 10));
  }
  return isIndexRun(leftParts);
}
function rejoinThousands(rows) {
  const rejoined = rows.map(rejoinLine);
  if (isIndexedValueFile(rejoined)) {
    return rejoined.map((line) => line.original);
  }
  return rejoined.map((line) => line.cells);
}
function qualifies(score) {
  return score.modal >= 2 && score.share >= DELIMITER_SHARE;
}
function looksLikeHeader(cells) {
  const filled = cells.filter((cell3) => cell3.text.length > 0);
  return filled.length > 0 && filled.every((cell3) => parseNumberToken(cell3.text) === null && parseDateToken(cell3.text) === null);
}
function chooseCommaSplit(raw) {
  const dated = raw.map(rejoinDates);
  const dateMerges = dated.reduce((sum, line) => sum + line.merges, 0);
  const plain = dated.map((line) => line.cells);
  const rejoined = rejoinThousands(plain);
  const thousandsMerges = plain.reduce((sum, line, index) => sum + line.length - (rejoined[index]?.length ?? line.length), 0);
  const rejoinedScore = scoreRows(rejoined);
  const plainScore = scoreRows(plain);
  const asPlain = { rows: plain, dateMerges, thousandsMerges: 0 };
  if (qualifies(rejoinedScore)) {
    const first = plain[0] ?? [];
    if (looksLikeHeader(first) && first.length > rejoinedScore.modal && qualifies(plainScore) && plainScore.modal === first.length) {
      return asPlain;
    }
    return { rows: rejoined, dateMerges, thousandsMerges };
  }
  if (rejoinedScore.modal >= 2 && qualifies(plainScore)) {
    return asPlain;
  }
  return null;
}
function scoreRows(rows) {
  const counts = /* @__PURE__ */ new Map();
  for (const row of rows) {
    counts.set(row.length, (counts.get(row.length) ?? 0) + 1);
  }
  let modal = 0;
  let modalLines = 0;
  for (const [count, lines] of counts) {
    if (lines > modalLines || lines === modalLines && count > modal) {
      modal = count;
      modalLines = lines;
    }
  }
  return { modal, share: modalLines / rows.length };
}
function splitTable(lines, log) {
  for (const candidate of DELIMITERS) {
    const raw = lines.map(
      (line) => candidate.delimiter === null ? splitOnWhitespace(line) : splitOnChar(line, candidate.delimiter)
    );
    const split = candidate.delimiter === "," ? chooseCommaSplit(raw) : qualifies(scoreRows(raw)) ? { rows: raw, dateMerges: 0, thousandsMerges: 0 } : null;
    if (split !== null) {
      const { modal } = scoreRows(split.rows);
      record(
        log,
        "detected-delimiter",
        "note",
        lines.length,
        () => `Split each line on ${candidate.description} into ${modal} columns.`
      );
      if (split.dateMerges > 0) {
        record(
          log,
          "rejoined-cells",
          "note",
          split.dateMerges + split.thousandsMerges,
          (n) => `Rejoined ${plural(n, "cell")} split by a comma inside a date or a number.`
        );
      }
      return split.rows;
    }
  }
  record(log, "detected-delimiter", "note", lines.length, () => "Read each line as one value.");
  return lines.map((line) => splitOnChar(line, "\n"));
}
function classifyCell(raw) {
  const text = raw.text;
  if (isMissingMarker(text)) {
    return { kind: "missing", text };
  }
  const token = parseNumberToken(text);
  if (token !== null) {
    return { kind: "number", text, token };
  }
  const date = parseDateToken(text);
  if (date !== null) {
    if (date.kind === "slash-candidate") {
      return { kind: "slash", text, candidate: date };
    }
    return { kind: "date", text, reading: date };
  }
  return { kind: "text", text };
}
function classifyTable(table, log) {
  const grid = table.map((row) => row.map(classifyCell));
  let unicodeMinus = 0;
  let parenthesized = 0;
  let currency = 0;
  let percent = 0;
  let magnitude = 0;
  let thousands = 0;
  let strippedTimes = 0;
  let twoDigitYears = 0;
  for (const row of grid) {
    for (const cell3 of row) {
      if (cell3.kind === "number") {
        const token = cell3.token;
        unicodeMinus += token.unicodeMinus ? 1 : 0;
        parenthesized += token.parenthesized ? 1 : 0;
        currency += token.currencySymbol !== null ? 1 : 0;
        percent += token.percent ? 1 : 0;
        magnitude += token.magnitude !== null ? 1 : 0;
        thousands += token.thousands ? 1 : 0;
      } else if (cell3.kind === "date") {
        strippedTimes += cell3.reading.strippedTime ? 1 : 0;
        twoDigitYears += cell3.reading.twoDigitYear ? 1 : 0;
      } else if (cell3.kind === "slash") {
        strippedTimes += cell3.candidate.strippedTime ? 1 : 0;
        twoDigitYears += cell3.candidate.twoDigitYear ? 1 : 0;
      }
    }
  }
  if (unicodeMinus > 0) {
    record(log, "unicode-minus", "note", unicodeMinus, (n) => `Read the Unicode minus sign as a negative in ${plural(n, "cell")}.`);
  }
  if (parenthesized > 0) {
    record(log, "parenthesized-negatives", "note", parenthesized, (n) => `Read parentheses as negatives in ${plural(n, "cell")}.`);
  }
  if (currency > 0) {
    record(log, "currency-symbols", "note", currency, (n) => `Removed currency symbols from ${plural(n, "cell")}.`);
  }
  if (percent > 0) {
    record(log, "percent-signs", "note", percent, (n) => `Removed percent signs from ${plural(n, "cell")}; 12% reads as 12.`);
  }
  if (magnitude > 0) {
    record(log, "magnitude-suffix", "note", magnitude, (n) => `Expanded K, M, or B suffixes in ${plural(n, "cell")}.`);
  }
  if (thousands > 0) {
    record(log, "thousands-separators", "note", thousands, (n) => `Removed thousands separators from ${plural(n, "cell")}.`);
  }
  if (strippedTimes > 0) {
    record(log, "stripped-times", "note", strippedTimes, (n) => `Dropped the time of day from ${plural(n, "date")}.`);
  }
  if (twoDigitYears > 0) {
    record(log, "two-digit-years", "note", twoDigitYears, (n) => `Read two-digit years as 2000 plus the digits in ${plural(n, "date")}.`);
  }
  return grid;
}
function resolveSlashDates(grid, options, log) {
  const candidates = [];
  for (const row of grid) {
    for (const cell3 of row) {
      if (cell3.kind === "slash") {
        candidates.push(cell3);
      }
    }
  }
  if (candidates.length === 0) {
    return null;
  }
  let dayFirst;
  if (options.dayFirst !== void 0) {
    dayFirst = options.dayFirst;
  } else {
    const dayInFirst = candidates.find((cell3) => cell3.candidate.first > MAX_MONTH);
    const dayInSecond = candidates.find((cell3) => cell3.candidate.second > MAX_MONTH);
    if (dayInFirst !== void 0 && dayInSecond !== void 0) {
      return {
        code: "unsupported-dates",
        message: `${dayInFirst.text} reads as day first and ${dayInSecond.text} reads as month first; the slash dates cannot share one order.`
      };
    }
    if (dayInFirst !== void 0) {
      dayFirst = true;
      record(
        log,
        "day-first-dates",
        "note",
        candidates.length,
        (n) => `Read ${plural(n, "slash date")} as day, month, year because ${dayInFirst.text} has a first part above ${MAX_MONTH}.`
      );
    } else if (dayInSecond !== void 0) {
      dayFirst = false;
      record(
        log,
        "month-first-dates",
        "note",
        candidates.length,
        (n) => `Read ${plural(n, "slash date")} as month, day, year because ${dayInSecond.text} has a second part above ${MAX_MONTH}.`
      );
    } else {
      dayFirst = false;
      record(
        log,
        "month-first-dates",
        "note",
        candidates.length,
        (n) => `Read ${plural(n, "slash date")} as month, day, year. Set dayFirst to read them as day, month, year.`
      );
    }
  }
  for (const row of grid) {
    for (let col = 0; col < row.length; col += 1) {
      const cell3 = row[col];
      if (cell3 === void 0 || cell3.kind !== "slash") {
        continue;
      }
      const reading = resolveSlashCandidate(cell3.candidate, dayFirst);
      row[col] = reading === null ? { kind: "text", text: cell3.text } : { kind: "date", text: cell3.text, reading };
    }
  }
  return null;
}
function carriesMarks(token) {
  return token.decimalPoint || token.currencySymbol !== null || token.percent || token.thousands;
}
function isHeaderCell(cell3, grid, col) {
  if (cell3.kind === "text") {
    return true;
  }
  if (cell3.kind === "number" && carriesMarks(cell3.token)) {
    return false;
  }
  if (cell3.kind !== "number" && cell3.kind !== "date") {
    return false;
  }
  const below = grid.slice(1).map((row) => cellAt(row, col)).filter((other) => other.kind === "number");
  return below.length > 0 && below.every((other) => carriesMarks(other.token));
}
function detectHeader(grid, options) {
  if (options.header !== void 0) {
    return options.header;
  }
  const row0 = grid[0];
  const row1 = grid[1];
  if (row0 === void 0 || row1 === void 0) {
    return false;
  }
  const headerCells = row0.map((cell3, col) => isHeaderCell(cell3, grid, col));
  if (headerCells.every(Boolean)) {
    return true;
  }
  const row1Parses = row1.every((cell3) => cell3.kind !== "text");
  return headerCells.some(Boolean) && row1Parses;
}
function splitHeader(grid, options, log) {
  if (!detectHeader(grid, options)) {
    return { header: null, rows: grid };
  }
  const header = (grid[0] ?? []).map((cell3) => cell3.text);
  record(log, "skipped-header", "note", 1, () => `Skipped the header row: ${header.join(", ")}.`);
  return { header, rows: grid.slice(1) };
}
function columnStats(rows, col) {
  const stats = { dates: 0, numbers: 0, missing: 0, texts: 0, distinct: /* @__PURE__ */ new Set() };
  for (const row of rows) {
    const cell3 = cellAt(row, col);
    switch (cell3.kind) {
      case "date":
        stats.dates += 1;
        break;
      case "number":
        stats.numbers += 1;
        break;
      case "missing":
        stats.missing += 1;
        break;
      default:
        stats.texts += 1;
    }
    if (cell3.kind !== "missing") {
      stats.distinct.add(labelKey(cell3.text));
    }
  }
  return stats;
}
function isIndexColumn(rows, col) {
  const values = [];
  for (const row of rows) {
    const cell3 = cellAt(row, col);
    if (cell3.kind === "missing") {
      continue;
    }
    if (cell3.kind !== "number") {
      return false;
    }
    values.push(cell3.token.value);
  }
  return isIndexRun(values);
}
function groupLabelTexts(rows, col) {
  const seen = /* @__PURE__ */ new Map();
  for (const row of rows) {
    const cell3 = cellAt(row, col);
    if (cell3.kind !== "missing" && !seen.has(labelKey(cell3.text))) {
      seen.set(labelKey(cell3.text), cell3.text.trim());
    }
  }
  return [...seen.values()];
}
function seriesName(header, col) {
  const name2 = header?.[col]?.trim();
  if (name2 === void 0 || name2.length === 0 || GENERIC_NAMES.has(name2.toLowerCase())) {
    return null;
  }
  return name2;
}
function assignRoles(rows, header, options, log) {
  const columnCount = rows.reduce((width, row) => Math.max(width, row.length), 0);
  const columns = Array.from({ length: columnCount }, (_, col) => col);
  const stats = columns.map((col) => columnStats(rows, col));
  const statsAt = (col) => stats[col] ?? { dates: 0, numbers: 0, missing: 0, texts: 0, distinct: /* @__PURE__ */ new Set() };
  const nameOf = (col) => columnName(header, col);
  const numberShare = (col) => (statsAt(col).numbers + statsAt(col).missing) / rows.length;
  if (columnCount === 1) {
    if (statsAt(0).numbers === 0 || numberShare(0) < HEADER_PARSE_SHARE) {
      return error("no-numbers", "The column holds no numbers.");
    }
    return {
      ok: true,
      value: {
        dateCol: null,
        groupCol: null,
        valueCol: 0,
        controlCol: null,
        summedCol: null,
        labels: null,
        groups: null,
        treatedFromOptions: false,
        name: seriesName(header, 0)
      }
    };
  }
  let dateCol = null;
  let bestDateShare = 0;
  for (const col of columns) {
    const share = statsAt(col).dates / rows.length;
    if (share >= HEADER_PARSE_SHARE && share > bestDateShare) {
      dateCol = col;
      bestDateShare = share;
    }
  }
  const isNumeric = (col) => col !== dateCol && statsAt(col).numbers > 0 && numberShare(col) >= HEADER_PARSE_SHARE;
  let groupCol = null;
  for (const col of columns) {
    if (col !== dateCol && statsAt(col).distinct.size === 2) {
      const remaining = columns.filter((other) => other !== col && isNumeric(other));
      if (remaining.length > 0) {
        groupCol = col;
        break;
      }
    }
  }
  let numeric = columns.filter((col) => col !== groupCol && isNumeric(col));
  const textColumns = columns.filter(
    (col) => col !== dateCol && col !== groupCol && statsAt(col).texts / rows.length >= HEADER_PARSE_SHARE
  );
  let indexCol = null;
  const firstNumeric = numeric[0];
  if (numeric.length >= 2 && firstNumeric !== void 0 && isIndexColumn(rows, firstNumeric)) {
    indexCol = firstNumeric;
    numeric = numeric.slice(1);
    record(log, "index-column", "note", 1, () => `Dropped ${nameOf(firstNumeric)} as a row index.`);
  }
  const activeColumns = columns.filter((col) => col !== indexCol);
  if (numeric.length === 0) {
    return error("no-numbers", "No column holds numbers.");
  }
  if (dateCol === null && groupCol === null && activeColumns.length === 2) {
    return error("no-date-column", COLUMN_SHAPE_MESSAGE);
  }
  let summedCol = null;
  const onlyText = textColumns[0];
  if (groupCol === null && textColumns.length === 1 && onlyText !== void 0 && statsAt(onlyText).distinct.size >= 3) {
    if (dateCol === null) {
      return error("group-count", COLUMN_SHAPE_MESSAGE);
    }
    summedCol = onlyText;
    const labelTexts = groupLabelTexts(rows, onlyText);
    record(
      log,
      "summed-labels",
      "note",
      labelTexts.length,
      (n) => `Added up ${plural(n, "label")} (${listNames(labelTexts)}) per date into one value.`
    );
  }
  if (groupCol !== null && numeric.length >= 2 || numeric.length >= 3) {
    return error("ambiguous-columns", COLUMN_SHAPE_MESSAGE);
  }
  let valueCol;
  let controlCol = null;
  let groups = null;
  let labels = null;
  let treatedFromOptions = false;
  const wanted = options.treatedLabel === void 0 ? null : labelKey(options.treatedLabel);
  if (groupCol !== null) {
    valueCol = numeric[0] ?? 0;
    const texts = groupLabelTexts(rows, groupCol);
    let treated = texts[0] ?? "";
    let controlLabel = texts[1] ?? "";
    if (wanted !== null && labelKey(controlLabel) === wanted) {
      [treated, controlLabel] = [controlLabel, treated];
      treatedFromOptions = true;
    } else if (wanted !== null && labelKey(treated) === wanted) {
      treatedFromOptions = true;
    }
    groups = { treated, control: controlLabel };
    labels = { treatedKey: labelKey(treated), controlKey: labelKey(controlLabel) };
  } else if (numeric.length === 2) {
    const first = numeric[0] ?? 0;
    const second = numeric[1] ?? 0;
    if (dateCol === null) {
      return error("no-date-column", COLUMN_SHAPE_MESSAGE);
    }
    valueCol = first;
    controlCol = second;
    if (wanted !== null && labelKey(nameOf(second)) === wanted) {
      valueCol = second;
      controlCol = first;
      treatedFromOptions = true;
    } else if (wanted !== null && labelKey(nameOf(first)) === wanted) {
      treatedFromOptions = true;
    }
    const treatedName = nameOf(valueCol);
    const controlName = nameOf(controlCol);
    groups = { treated: treatedName, control: controlName };
    record(
      log,
      "wide-columns",
      "note",
      2,
      () => `Treated: ${treatedName}. Comparison: ${controlName}. Swap the two if this is backwards.`
    );
  } else {
    valueCol = numeric[0] ?? 0;
  }
  const used = /* @__PURE__ */ new Set([valueCol]);
  if (dateCol !== null) {
    used.add(dateCol);
  }
  if (groupCol !== null) {
    used.add(groupCol);
  }
  if (indexCol !== null) {
    used.add(indexCol);
  }
  if (controlCol !== null) {
    used.add(controlCol);
  }
  if (summedCol !== null) {
    used.add(summedCol);
  }
  const ignored = columns.filter((col) => !used.has(col));
  if (ignored.length > 0) {
    const roleNames = [];
    if (dateCol !== null) {
      roleNames.push(`${nameOf(dateCol)} as dates`);
    }
    if (groupCol !== null) {
      roleNames.push(`${nameOf(groupCol)} as groups`);
    }
    if (summedCol !== null) {
      roleNames.push(`${nameOf(summedCol)} as labels added up per date`);
    }
    roleNames.push(`${nameOf(valueCol)} as values`);
    if (controlCol !== null) {
      roleNames.push(`${nameOf(controlCol)} as the comparison`);
    }
    record(
      log,
      "used-columns",
      "note",
      ignored.length,
      () => `Used ${roleNames.join(", ")}. Ignored ${ignored.map(nameOf).join(", ")}.`
    );
  }
  if (groupCol !== null && dateCol === null && labels !== null) {
    const counts = [0, 0];
    for (const row of rows) {
      const key = labelKey(cellAt(row, groupCol).text);
      if (key === labels.treatedKey) {
        counts[0] = (counts[0] ?? 0) + 1;
      } else if (key === labels.controlKey) {
        counts[1] = (counts[1] ?? 0) + 1;
      }
    }
    if (counts[0] !== counts[1]) {
      return error(
        "unequal-groups",
        `Without dates the groups must have the same number of rows; ${groups?.treated ?? ""} has ${counts[0] ?? 0} and ${groups?.control ?? ""} has ${counts[1] ?? 0}.`
      );
    }
    record(
      log,
      "aligned-by-position",
      "warning",
      counts[0] ?? 0,
      (n) => `No date column, so the ${plural(n, "row")} of each group were paired by position.`
    );
  }
  return {
    ok: true,
    value: {
      dateCol,
      groupCol,
      valueCol,
      controlCol,
      summedCol,
      labels,
      groups,
      treatedFromOptions,
      name: seriesName(header, valueCol)
    }
  };
}
function valueTokens(rows, valueCol) {
  const tokens = [];
  for (const row of rows) {
    const cell3 = cellAt(row, valueCol);
    if (cell3.kind === "number") {
      tokens.push(cell3.token);
    }
  }
  return tokens;
}
function readValue(cell3) {
  if (cell3.kind === "number") {
    return { value: cell3.token.value, unreadable: false };
  }
  if (cell3.kind === "missing") {
    return { value: null, unreadable: false };
  }
  return { value: null, unreadable: true };
}
function cleanRows(rows, roles, log) {
  const treated = [];
  const control = [];
  const labelTexts = [];
  let labelRows = 0;
  let missing = 0;
  let unreadableRows = 0;
  let examined = 0;
  for (const row of rows) {
    let day = null;
    let monthGranularity = false;
    if (roles.dateCol !== null) {
      const cell3 = cellAt(row, roles.dateCol);
      if (cell3.kind !== "date") {
        labelRows += 1;
        labelTexts.push(cell3.text.length > 0 ? cell3.text : "(blank)");
        continue;
      }
      day = cell3.reading.day;
      monthGranularity = cell3.reading.monthGranularity;
    }
    let target = treated;
    if (roles.groupCol !== null && roles.labels !== null) {
      const cell3 = cellAt(row, roles.groupCol);
      const key = labelKey(cell3.text);
      if (cell3.kind === "missing" || key !== roles.labels.treatedKey && key !== roles.labels.controlKey) {
        labelRows += 1;
        labelTexts.push(cell3.text.length > 0 ? cell3.text : "(blank)");
        continue;
      }
      target = key === roles.labels.treatedKey ? treated : control;
    }
    examined += 1;
    if (roles.controlCol !== null) {
      const treatedValue = readValue(cellAt(row, roles.valueCol));
      const controlValue = readValue(cellAt(row, roles.controlCol));
      if (treatedValue.unreadable || controlValue.unreadable) {
        unreadableRows += 1;
      }
      missing += (treatedValue.value === null ? 1 : 0) + (controlValue.value === null ? 1 : 0);
      treated.push({ day, monthGranularity, value: treatedValue.value });
      control.push({ day, monthGranularity, value: controlValue.value });
      continue;
    }
    const reading = readValue(cellAt(row, roles.valueCol));
    if (reading.unreadable) {
      unreadableRows += 1;
      missing += 1;
      continue;
    }
    if (reading.value === null) {
      missing += 1;
    }
    target.push({ day, monthGranularity, value: reading.value });
  }
  if (labelRows > 0) {
    record(
      log,
      "dropped-label-rows",
      "warning",
      labelRows,
      (n) => `Dropped ${plural(n, "row")} without a date or group: ${listNames(labelTexts)}.`
    );
  }
  if (examined > 0 && unreadableRows / examined > UNREADABLE_SHARE) {
    return error(
      "unreadable-rows",
      `${plural(unreadableRows, "row")} of ${examined} had a value that is neither a number nor a missing marker.`
    );
  }
  if (missing > 0) {
    record(
      log,
      "missing-values",
      "warning",
      missing,
      (n) => `${plural(n, "value was", "values were")} missing or unreadable and left as missing periods.`
    );
  }
  const hasControl = roles.groupCol !== null || roles.controlCol !== null;
  if (hasControl && roles.dateCol === null && treated.length !== control.length) {
    return error(
      "unequal-groups",
      `Without dates the groups must have the same number of rows; the treated group has ${treated.length} and the comparison group has ${control.length}.`
    );
  }
  return { ok: true, value: { treated, control: hasControl ? control : null } };
}
function dayOf(row) {
  return row.day ?? 0;
}
function orderRows(rows, log) {
  const days = rows.map(dayOf);
  let decreasing = rows.length > 1;
  let nonDecreasing = true;
  for (let i = 1; i < days.length; i += 1) {
    const previous = days[i - 1] ?? 0;
    const current = days[i] ?? 0;
    if (current >= previous) {
      decreasing = false;
    }
    if (current < previous) {
      nonDecreasing = false;
    }
  }
  if (decreasing) {
    record(log, "reversed-newest-first", "note", rows.length, (n) => `Reversed ${plural(n, "row")} that ran newest first.`);
    return [...rows].reverse();
  }
  if (nonDecreasing) {
    return rows;
  }
  record(log, "sorted-by-date", "warning", rows.length, (n) => `Sorted ${plural(n, "row")} by date; the rows were out of order.`);
  return [...rows].sort((a, b) => dayOf(a) - dayOf(b));
}
function sumSharedDates(rows) {
  const byDay = /* @__PURE__ */ new Map();
  for (const row of rows) {
    const day = dayOf(row);
    const existing = byDay.get(day);
    if (existing === void 0) {
      byDay.set(day, { row: { ...row }, count: 1 });
      continue;
    }
    existing.count += 1;
    if (row.value !== null) {
      existing.row.value = existing.row.value === null ? row.value : existing.row.value + row.value;
    }
  }
  let merged = 0;
  for (const group2 of byDay.values()) {
    if (group2.count > 1) {
      merged += group2.count;
    }
  }
  return { rows: [...byDay.values()].map((group2) => group2.row), merged };
}
function periodWord(frequency) {
  switch (frequency) {
    case "daily":
      return "day";
    case "weekly":
      return "week";
    case "monthly":
      return "month";
    default:
      return "date";
  }
}
function detectFrequency(rows) {
  if (rows.length < 2) {
    return { frequency: "unknown", mode: null };
  }
  const days = rows.map(dayOf);
  const diffs = [];
  for (let i = 1; i < days.length; i += 1) {
    diffs.push((days[i] ?? 0) - (days[i - 1] ?? 0));
  }
  const mode = mostCommon2(diffs);
  if (mode === 1) {
    return { frequency: "daily", mode };
  }
  if (mode === DAYS_PER_WEEK) {
    return { frequency: "weekly", mode };
  }
  const monthSpacing = diffs.every((diff) => diff >= MONTH_SPACING_MIN && diff <= MONTH_SPACING_MAX);
  const firstDay = civilDate(days[0] ?? 0).day;
  const sameDayOfMonth = days.every((day) => civilDate(day).day === firstDay);
  const monthForms = rows.every((row) => row.monthGranularity);
  if (monthSpacing || sameDayOfMonth || monthForms) {
    return { frequency: "monthly", mode };
  }
  return { frequency: "unknown", mode };
}
function sameBucket(a, b, frequency) {
  switch (frequency) {
    case "daily":
      return mondayOf(a) === mondayOf(b);
    case "weekly":
      return monthKey(a) === monthKey(b);
    case "monthly":
      return civilDate(a).year === civilDate(b).year;
  }
}
function removeTotals(rows, frequency, mode, log) {
  const kept = [];
  const droppedDates = [];
  for (let i = 0; i < rows.length; i += 1) {
    const row = rows[i];
    if (row === void 0) {
      continue;
    }
    const previous = kept[kept.length - 1];
    const next = rows[i + 1];
    const offPrevious = previous === void 0 || dayOf(row) - dayOf(previous) !== mode;
    const offNext = next === void 0 || dayOf(next) - dayOf(row) !== mode;
    if (offPrevious && offNext && row.value !== null) {
      const parts = kept.filter((other) => other.value !== null && sameBucket(dayOf(other), dayOf(row), frequency));
      if (parts.length >= 2) {
        const sum = parts.reduce((total, other) => total + (other.value ?? 0), 0);
        if (Math.abs(row.value - sum) <= TOTALS_TOLERANCE * Math.abs(sum)) {
          droppedDates.push(toIsoDate(dayOf(row)));
          continue;
        }
      }
    }
    kept.push(row);
  }
  if (droppedDates.length > 0) {
    record(
      log,
      "dropped-inferred-totals",
      "warning",
      droppedDates.length,
      (n) => `Dropped ${plural(n, "off-cadence row")} equal to the sum of the rows before it: ${listNames(droppedDates)}.`
    );
  }
  return kept;
}
function rollUpDaily(rows, weekendFree, rollup, log) {
  const weeks = /* @__PURE__ */ new Map();
  for (const row of rows) {
    const monday = mondayOf(dayOf(row));
    const values = weeks.get(monday) ?? [];
    if (row.value !== null) {
      values.push(row.value);
    }
    weeks.set(monday, values);
  }
  const mondays = [...weeks.keys()].sort((a, b) => a - b);
  const result = [];
  const partialInterior = [];
  let droppedEdges = 0;
  mondays.forEach((monday, position) => {
    const values = weeks.get(monday) ?? [];
    const complete = values.length === DAYS_PER_WEEK || weekendFree && values.length === WEEKDAYS_PER_WEEK;
    const edge = position === 0 || position === mondays.length - 1;
    if (!complete && edge) {
      droppedEdges += 1;
      return;
    }
    let value;
    if (complete || rollup === "mean") {
      const total = values.reduce((sum, v) => sum + v, 0);
      value = values.length === 0 ? null : rollup === "sum" ? total : total / values.length;
    } else {
      value = null;
    }
    if (!complete && rollup === "sum") {
      partialInterior.push(toIsoDate(monday));
    }
    result.push({ day: monday, monthGranularity: false, value });
  });
  record(
    log,
    "rolled-daily-to-weekly",
    "note",
    result.length,
    (n) => `Rolled daily values into ${plural(n, "week")} starting Monday by ${rollup}.`
  );
  if (droppedEdges > 0) {
    record(
      log,
      "dropped-partial-weeks",
      "warning",
      droppedEdges,
      (n) => `Dropped ${plural(n, "incomplete week")} at the start or end of the data.`
    );
  }
  if (partialInterior.length > 0) {
    record(
      log,
      "partial-weeks-as-missing",
      "warning",
      partialInterior.length,
      (n) => `${plural(n, "interior week")} had fewer days than a full week and became missing periods: ${listNames(partialInterior)}.`
    );
  }
  return result;
}
function normalizeMonths(rows, log) {
  let moved = 0;
  const result = [];
  for (const row of rows) {
    const day = dayOf(row);
    if (civilDate(day).day !== 1) {
      moved += 1;
    }
    result.push({ ...row, day: monthStart(day) });
  }
  if (moved > 0) {
    record(
      log,
      "month-dates-normalized",
      "note",
      moved,
      (n) => `Moved ${plural(n, "monthly date")} to the first of its month.`
    );
  }
  return result;
}
function enumerateExpected(first, last, frequency) {
  const expected = [];
  if (frequency === "weekly") {
    for (let day = first; day <= last; day += DAYS_PER_WEEK) {
      expected.push(day);
    }
  } else {
    for (let key = monthKey(first); key <= monthKey(last); key += 1) {
      expected.push(monthKeyStart(key));
    }
  }
  return expected;
}
function buildTimeline(present2, frequency, log) {
  const first = present2[0];
  const last = present2[present2.length - 1];
  if (first === void 0 || last === void 0) {
    return { days: [], gaps: [] };
  }
  const expected = enumerateExpected(first, last, frequency);
  const presentSet = new Set(present2);
  const runs = [];
  expected.forEach((day, position) => {
    if (presentSet.has(day)) {
      return;
    }
    const current = runs[runs.length - 1];
    if (current !== void 0 && current.start + current.length === position) {
      current.length += 1;
    } else {
      runs.push({ start: position, length: 1 });
    }
  });
  let keptStart = 0;
  let keptEnd = expected.length - 1;
  const longRuns = runs.filter((run) => run.length > MAX_GAP_RUN);
  if (longRuns.length > 0) {
    const stretches = [];
    let stretchStart = 0;
    for (const run of longRuns) {
      stretches.push([stretchStart, run.start - 1]);
      stretchStart = run.start + run.length;
    }
    stretches.push([stretchStart, expected.length - 1]);
    let best = [keptStart, keptEnd];
    let bestLength = -1;
    for (const stretch of stretches) {
      const length = stretch[1] - stretch[0];
      if (length > bestLength) {
        best = stretch;
        bestLength = length;
      }
    }
    [keptStart, keptEnd] = best;
  }
  const days = expected.slice(keptStart, keptEnd + 1);
  const gaps = [];
  let keptMissing = 0;
  for (const run of runs) {
    const startDay = expected[run.start];
    if (startDay === void 0) {
      continue;
    }
    const inside = run.start >= keptStart && run.start + run.length - 1 <= keptEnd;
    if (inside) {
      gaps.push({ afterIndex: run.start - 1 - keptStart, start: toIsoDate(startDay), length: run.length, treatment: "kept-as-missing" });
      keptMissing += run.length;
    } else {
      gaps.push({ afterIndex: null, start: toIsoDate(startDay), length: run.length, treatment: "dropped" });
    }
  }
  if (keptMissing > 0) {
    record(
      log,
      "missing-periods",
      "warning",
      keptMissing,
      (n) => `${plural(n, "period was", "periods were")} absent from the date sequence and inserted as missing.`
    );
  }
  if (longRuns.length > 0) {
    const keptFirst = days[0];
    const keptLast = days[days.length - 1];
    const droppedRows = present2.filter((day) => day < (keptFirst ?? day) || day > (keptLast ?? day)).length;
    record(
      log,
      "cut-to-contiguous-run",
      "warning",
      droppedRows,
      (n) => `Kept ${toIsoDate(keptFirst ?? first)} to ${toIsoDate(keptLast ?? last)} (${plural(days.length, "period")}) and dropped ${plural(n, "row")} beyond a gap longer than ${MAX_GAP_RUN} periods.`
    );
  }
  return { days, gaps };
}
function toPeriods(days, values) {
  return days.map((day, index) => ({ index, date: toIsoDate(day), value: values.get(day) ?? null }));
}
function buildUndated(cleaned) {
  const periods = cleaned.treated.map((row, index) => ({ index, date: null, value: row.value }));
  const control = cleaned.control === null ? null : cleaned.control.map((row, index) => ({ index, date: null, value: row.value }));
  return { periods, control, frequency: "unknown", gaps: [], treatedOnly: 0, controlOnly: 0 };
}
function buildDated(cleaned, options, labelsCollapsed, log) {
  const rollup = options.rollup ?? "sum";
  const summedTreated = sumSharedDates(orderRows(cleaned.treated, log));
  const summedControl = cleaned.control === null ? null : sumSharedDates(orderRows(cleaned.control, log));
  let treated = summedTreated.rows;
  let control = summedControl === null ? null : summedControl.rows;
  const detected = detectFrequency(treated);
  let frequency = detected.frequency;
  const mode = detected.mode;
  const unit2 = periodWord(frequency);
  const noteSums = (merged) => {
    if (merged > 0 && !labelsCollapsed) {
      record(
        log,
        "summed-shared-dates",
        "note",
        merged,
        (n) => `Added up ${plural(n, "row")} that shared a date into one value per ${unit2}.`
      );
    }
  };
  noteSums(summedTreated.merged + (summedControl?.merged ?? 0));
  if (frequency === "unknown") {
    if (mode !== null) {
      record(
        log,
        "irregular-spacing",
        "warning",
        treated.length,
        () => `The dates are unevenly spaced (most common step ${plural(mode, "day")}), so rows were used in order as evenly spaced periods.`
      );
    }
  } else if (mode !== null) {
    const regular = frequency;
    treated = removeTotals(treated, regular, mode, log);
    control = control === null ? null : removeTotals(control, regular, mode, log);
    if (regular === "daily") {
      const everyRow = control === null ? treated : [...treated, ...control];
      const weekendFree = everyRow.every((row) => !isWeekend(dayOf(row)));
      treated = rollUpDaily(treated, weekendFree, rollup, log);
      control = control === null ? null : rollUpDaily(control, weekendFree, rollup, log);
      frequency = "weekly";
    } else if (regular === "monthly") {
      const monthlyTreated = sumSharedDates(normalizeMonths(treated, log));
      const monthlyControl = control === null ? null : sumSharedDates(normalizeMonths(control, log));
      treated = monthlyTreated.rows;
      control = monthlyControl === null ? null : monthlyControl.rows;
      noteSums(monthlyTreated.merged + (monthlyControl?.merged ?? 0));
    }
  }
  const treatedValues = new Map(treated.map((row) => [dayOf(row), row.value]));
  const controlValues = control === null ? null : new Map(control.map((row) => [dayOf(row), row.value]));
  const union = [.../* @__PURE__ */ new Set([...treatedValues.keys(), ...controlValues === null ? [] : controlValues.keys()])].sort((a, b) => a - b);
  const unionFirst = union[0];
  if (frequency === "weekly" && unionFirst !== void 0 && union.some((day) => (day - unionFirst) % DAYS_PER_WEEK !== 0)) {
    frequency = "unknown";
    record(
      log,
      "irregular-spacing",
      "warning",
      union.length,
      () => "A date falls off the weekly cadence, so rows were used in order as evenly spaced periods."
    );
  }
  let timeline;
  if (frequency === "weekly" || frequency === "monthly") {
    timeline = buildTimeline(union, frequency, log);
  } else {
    timeline = { days: union, gaps: [] };
  }
  let treatedOnly = 0;
  let controlOnly = 0;
  if (controlValues !== null) {
    for (const day of timeline.days) {
      const inTreated = treatedValues.has(day);
      const inControl = controlValues.has(day);
      if (inTreated && !inControl) {
        treatedOnly += 1;
      } else if (inControl && !inTreated) {
        controlOnly += 1;
      }
    }
  }
  return {
    periods: toPeriods(timeline.days, treatedValues),
    control: controlValues === null ? null : toPeriods(timeline.days, controlValues),
    frequency,
    gaps: timeline.gaps,
    treatedOnly,
    controlOnly
  };
}

// src/engine/format.ts
var MAX_DECIMALS = 12;
function halfWidth(interval) {
  return (interval.upper - interval.lower) / 2;
}
function toPoints(fraction) {
  return fraction * 100;
}
function percentDecimals(x, hw) {
  if (Math.abs(x) >= 1 || hw >= 1) return 0;
  if (hw >= 0.1) return 1;
  return 2;
}
function formatPercent(x, hw) {
  if (Math.abs(x) < 1 && hw >= 1) return "under 1%";
  return percentToken(x, percentDecimals(x, hw));
}
function formatPercentBound(bound, point, hw) {
  return percentToken(bound, percentDecimals(point, hw));
}
function formatPercentRange(lower, upper, point, hw) {
  return `${formatPercentBound(lower, point, hw)} to ${formatPercentBound(upper, point, hw)}`;
}
function absoluteDecimals(hw) {
  if (!Number.isFinite(hw) || hw <= 0) return 0;
  const d = 1 - Math.floor(Math.log10(hw));
  return Math.min(MAX_DECIMALS, Math.max(0, d));
}
function formatAbsolute(x, hw, style) {
  return withUnit(formatFixed(x, absoluteDecimals(hw)), style, "difference");
}
function formatLevel(x, hw, style) {
  return withUnit(formatFixed(x, absoluteDecimals(hw)), style, "level");
}
function formatAbsoluteRange(lower, upper, hw, style) {
  return `${formatAbsolute(lower, hw, style)} to ${formatAbsolute(upper, hw, style)}`;
}
function formatFixed(x, decimals) {
  const digits = fixed(x, decimals);
  const negative = digits.startsWith("-");
  const unsigned = negative ? digits.slice(1) : digits;
  const dot3 = unsigned.indexOf(".");
  const whole = dot3 < 0 ? unsigned : unsigned.slice(0, dot3);
  const fraction = dot3 < 0 ? "" : unsigned.slice(dot3);
  const grouped = whole.replace(/\B(?=(\d{3})+$)/g, ",");
  return `${negative ? "-" : ""}${grouped}${fraction}`;
}
function formatShare(strength) {
  return `${fixed(strength * 100, 0)}%`;
}
function formatCoefficient(phi) {
  return fixed(phi, 2);
}
function formatCount(n) {
  return fixed(n, 0);
}
function percentToken(x, decimals) {
  const digits = fixed(x, decimals);
  if (Number(digits) === 0) return "0%";
  return `${digits}%`;
}
function fixed(x, decimals) {
  const digits = x.toFixed(decimals);
  if (digits.startsWith("-") && Number(digits) === 0) return digits.slice(1);
  return digits;
}
function withUnit(body, style, role) {
  if (style.unit === "currency" && style.currencySymbol !== null) {
    return body.startsWith("-") ? `-${style.currencySymbol}${body.slice(1)}` : `${style.currencySymbol}${body}`;
  }
  if (style.unit === "percent") return role === "level" ? `${body}%` : `${body} points`;
  return body;
}

// src/engine/readings.ts
function percentUnitsAvailable(preMean, preSd) {
  if (preMean === null || preSd === null) {
    return false;
  }
  return preMean > 0 && preMean > PERCENT_FLOOR_MULTIPLE * preSd;
}
function applicable(mAbs) {
  return mAbs !== null && Number.isFinite(mAbs);
}
function effectReading(lo, hi, mAbs, noiseSd) {
  if (lo > 0) {
    return { effect: "positive", basis: "interval" };
  }
  if (hi < 0) {
    return { effect: "negative", basis: "interval" };
  }
  if (applicable(mAbs)) {
    if (-mAbs < lo && hi < mAbs) {
      return { effect: "near-zero", basis: "threshold" };
    }
    return { effect: "uncertain", basis: "interval" };
  }
  const band = noiseSd * NEAR_ZERO_NOISE_MULTIPLE;
  if (-band < lo && hi < band) {
    return { effect: "near-zero", basis: "noise" };
  }
  return { effect: "uncertain", basis: "interval" };
}
function thresholdState(lo, hi, g, mAbs) {
  if (!applicable(mAbs)) {
    return "not-assessed";
  }
  const sLo = g > 0 ? lo : -hi;
  const sHi = g > 0 ? hi : -lo;
  if (sLo >= mAbs) {
    return "meets";
  }
  if (sHi < mAbs) {
    return "clearly-below";
  }
  return "possibly-below";
}

// src/engine/math.ts
var SingularDesignError = class extends Error {
  constructor(message = "The design matrix has a column with no independent variation.") {
    super(message);
    this.name = "SingularDesignError";
  }
};
var SINGULAR_RELATIVE = 1e-12;
function at(xs, i) {
  return xs[i];
}
function rowAt(m, i) {
  return m[i];
}
function zeros(n) {
  return new Array(n).fill(0);
}
function matrix(rows, cols) {
  return Array.from({ length: rows }, () => zeros(cols));
}
function dot(a, b) {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    s += at(a, i) * at(b, i);
  }
  return s;
}
function multiply(A, x) {
  return A.map((row) => dot(row, x));
}
function multiplyMatrices(A, B) {
  const rows = A.length;
  const inner = B.length;
  const cols = inner === 0 ? 0 : rowAt(B, 0).length;
  const out = matrix(rows, cols);
  for (let i = 0; i < rows; i++) {
    const a = rowAt(A, i);
    const o = at2(out, i);
    for (let m = 0; m < inner; m++) {
      const f = at(a, m);
      if (f === 0) continue;
      const b = rowAt(B, m);
      for (let j = 0; j < cols; j++) {
        o[j] = at(o, j) + f * at(b, j);
      }
    }
  }
  return out;
}
function at2(m, i) {
  return m[i];
}
function mean(xs) {
  if (xs.length === 0) {
    throw new RangeError("mean needs at least one value.");
  }
  let sum = 0;
  for (const x of xs) {
    sum += x;
  }
  return sum / xs.length;
}
function variance(xs) {
  if (xs.length < 2) {
    throw new RangeError("variance needs at least two values.");
  }
  const m = mean(xs);
  let ss = 0;
  for (const x of xs) {
    ss += (x - m) * (x - m);
  }
  return ss / (xs.length - 1);
}
function sd(xs) {
  return Math.sqrt(variance(xs));
}
function ols(X, y) {
  const n = X.length;
  const k = n === 0 ? 0 : rowAt(X, 0).length;
  if (n === 0 || k === 0) {
    throw new RangeError("ols needs at least one row and one column.");
  }
  if (y.length !== n) {
    throw new RangeError("ols needs one y value per design row.");
  }
  for (const row of X) {
    if (row.length !== k) {
      throw new RangeError("ols needs every design row to have the same length.");
    }
  }
  if (n < k) {
    throw new SingularDesignError("The design matrix has fewer rows than columns.");
  }
  const scale = columnScales(X, k);
  const A = X.map((row) => row.map((v, j) => v / at(scale, j)));
  const z = [...y];
  let largestNorm = 0;
  for (let j = 0; j < k; j++) {
    largestNorm = Math.max(largestNorm, Math.sqrt(columnSumOfSquares(A, j, 0)));
  }
  for (let j = 0; j < k; j++) {
    const norm = Math.sqrt(columnSumOfSquares(A, j, j));
    if (norm <= SINGULAR_RELATIVE * largestNorm) {
      throw new SingularDesignError();
    }
    const pivot = at(at2(A, j), j);
    const alpha = pivot > 0 ? -norm : norm;
    const v = zeros(n - j);
    v[0] = pivot - alpha;
    for (let i = j + 1; i < n; i++) {
      v[i - j] = at(at2(A, i), j);
    }
    const vv = dot(v, v);
    for (let l = j + 1; l < k; l++) {
      let s = 0;
      for (let i = j; i < n; i++) {
        s += at(v, i - j) * at(at2(A, i), l);
      }
      const f = 2 * s / vv;
      for (let i = j; i < n; i++) {
        const row = at2(A, i);
        row[l] = at(row, l) - f * at(v, i - j);
      }
    }
    let sz = 0;
    for (let i = j; i < n; i++) {
      sz += at(v, i - j) * at(z, i);
    }
    const fz = 2 * sz / vv;
    for (let i = j; i < n; i++) {
      z[i] = at(z, i) - fz * at(v, i - j);
    }
    at2(A, j)[j] = alpha;
    for (let i = j + 1; i < n; i++) {
      at2(A, i)[j] = 0;
    }
  }
  const betaScaled = backSubstitute(A, z.slice(0, k), k);
  const rInverse = matrix(k, k);
  for (let j = 0; j < k; j++) {
    const e = zeros(k);
    e[j] = 1;
    const column = backSubstitute(A, e, k);
    for (let i = 0; i < k; i++) {
      at2(rInverse, i)[j] = at(column, i);
    }
  }
  const xtxInverse = matrix(k, k);
  for (let a = 0; a < k; a++) {
    for (let b = 0; b <= a; b++) {
      const value = dot(at2(rInverse, a), at2(rInverse, b)) / (at(scale, a) * at(scale, b));
      at2(xtxInverse, a)[b] = value;
      at2(xtxInverse, b)[a] = value;
    }
  }
  const beta = betaScaled.map((value, j) => value / at(scale, j));
  const fitted = X.map((row) => dot(row, beta));
  const residuals = y.map((value, i) => value - at(fitted, i));
  const hat = X.map((row) => dot(row, multiply(xtxInverse, row)));
  const rss = dot(residuals, residuals);
  return { beta, fitted, residuals, hat, xtxInverse, n, k, df: n - k, rss };
}
function columnScales(X, k) {
  const scale = zeros(k);
  for (let j = 0; j < k; j++) {
    const first = at(rowAt(X, 0), j);
    let constant = true;
    let largest = 0;
    for (const row of X) {
      const v = at(row, j);
      if (v !== first) constant = false;
      largest = Math.max(largest, Math.abs(v));
    }
    scale[j] = constant || largest === 0 ? 1 : largest;
  }
  return scale;
}
function columnSumOfSquares(A, j, fromRow) {
  let s = 0;
  for (let i = fromRow; i < A.length; i++) {
    const v = at(rowAt(A, i), j);
    s += v * v;
  }
  return s;
}
function backSubstitute(A, b, k) {
  const x = zeros(k);
  for (let i = k - 1; i >= 0; i--) {
    const row = rowAt(A, i);
    let s = at(b, i);
    for (let j = i + 1; j < k; j++) {
      s -= at(row, j) * at(x, j);
    }
    x[i] = s / at(row, i);
  }
  return x;
}
function phiPowers(times, phi) {
  let largest = 0;
  for (const t of times) {
    for (const s of times) {
      largest = Math.max(largest, Math.abs(t - s));
    }
  }
  const powers = zeros(largest + 1);
  powers[0] = 1;
  for (let d = 1; d <= largest; d++) {
    powers[d] = at(powers, d - 1) * phi;
  }
  return powers;
}
function omegaProducts(fit2, design, phi) {
  const { rows: X, times } = design;
  const n = fit2.n;
  const k = fit2.k;
  const powers = phiPowers(times, phi);
  const omegaX = matrix(n, k);
  for (let b = 0; b < n; b++) {
    const tb = at(times, b);
    const target = at2(omegaX, b);
    for (let i = 0; i < n; i++) {
      const w = at(powers, Math.abs(at(times, i) - tb));
      if (w === 0) continue;
      const xi = rowAt(X, i);
      for (let a = 0; a < k; a++) {
        target[a] = at(target, a) + w * at(xi, a);
      }
    }
  }
  const xOmegaX = matrix(k, k);
  for (let b = 0; b < n; b++) {
    const ox = at2(omegaX, b);
    const xb = rowAt(X, b);
    for (let a = 0; a < k; a++) {
      const row = at2(xOmegaX, a);
      for (let c = 0; c < k; c++) {
        row[c] = at(row, c) + at(ox, a) * at(xb, c);
      }
    }
  }
  const m = matrix(k, n);
  for (let c = 0; c < k; c++) {
    const inv = rowAt(fit2.xtxInverse, c);
    const row = at2(m, c);
    for (let b = 0; b < n; b++) {
      row[b] = dot(inv, at2(omegaX, b));
    }
  }
  let traceHOmega = 0;
  for (let a = 0; a < n; a++) {
    traceHOmega += hOmega(X, m, a, a);
  }
  return { powers, xOmegaX, m, traceHOmega };
}
function hOmega(X, m, a, b) {
  const xa = rowAt(X, a);
  let s = 0;
  for (let c = 0; c < xa.length; c++) {
    s += at(xa, c) * at(rowAt(m, c), b);
  }
  return s;
}
function expectedAutocorrelation(fit2, design, phi) {
  const { rows: X, times } = design;
  const n = fit2.n;
  const products = omegaProducts(fit2, design, phi);
  const A = multiplyMatrices(multiplyMatrices(fit2.xtxInverse, products.xOmegaX), fit2.xtxInverse);
  let numerator = 0;
  for (let i = 1; i < n; i++) {
    if (at(times, i) - at(times, i - 1) !== 1) continue;
    const hOmegaH = dot(rowAt(X, i), multiply(A, rowAt(X, i - 1)));
    numerator += at(products.powers, 1) - hOmega(X, products.m, i, i - 1) - hOmega(X, products.m, i - 1, i) + hOmegaH;
  }
  return numerator / (n - products.traceHOmega);
}
function ar1Coefficient(fit2, design) {
  const e = fit2.residuals;
  const times = design.times;
  const n = fit2.n;
  const total = dot(e, e);
  if (total <= 0) {
    return 0;
  }
  let lagged = 0;
  for (let i = 1; i < n; i++) {
    if (at(times, i) - at(times, i - 1) === 1) {
      lagged += at(e, i) * at(e, i - 1);
    }
  }
  const rho = lagged / total;
  if (rho <= expectedAutocorrelation(fit2, design, 0)) {
    return 0;
  }
  let matched;
  if (rho >= expectedAutocorrelation(fit2, design, PHI_MAX)) {
    matched = PHI_MAX;
  } else {
    let lo = 0;
    let hi = PHI_MAX;
    for (let step2 = 0; step2 < PHI_ITERATIONS; step2++) {
      const mid = (lo + hi) / 2;
      if (expectedAutocorrelation(fit2, design, mid) < rho) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    matched = (lo + hi) / 2;
  }
  if (matched <= 0) {
    return 0;
  }
  return Math.min(PHI_MAX, matched + (1 + 3 * matched) / n);
}
function ar1Covariance(fit2, design, phi) {
  const products = omegaProducts(fit2, design, phi);
  const sigma2 = fit2.rss / (fit2.n - products.traceHOmega);
  const sandwich = multiplyMatrices(multiplyMatrices(fit2.xtxInverse, products.xOmegaX), fit2.xtxInverse);
  const V = sandwich.map((row) => row.map((v) => sigma2 * v));
  return { V, sigma2, phi };
}
function effectiveDf(df, phi) {
  return Math.max(DF_MIN, df * (1 - phi) / (1 + phi));
}
function linearCombination(fit2, V, c) {
  const estimate = dot(c, fit2.beta);
  const quadratic = dot(c, multiply(V, c));
  return { estimate, se: Math.sqrt(Math.max(0, quadratic)) };
}
function effectWeights(fit2, design, c) {
  const g = multiply(fit2.xtxInverse, c);
  const weights = /* @__PURE__ */ new Map();
  design.rows.forEach((row, i) => {
    weights.set(at(design.times, i), dot(g, row));
  });
  return weights;
}
function differenceSe(a, b, phi, sigma2) {
  const times = [.../* @__PURE__ */ new Set([...a.keys(), ...b.keys()])];
  const d = times.map((t) => (b.get(t) ?? 0) - (a.get(t) ?? 0));
  const powers = phiPowers(times, phi);
  let total = 0;
  for (let i = 0; i < times.length; i++) {
    for (let j = 0; j < times.length; j++) {
      total += at(d, i) * at(d, j) * at(powers, Math.abs(at(times, i) - at(times, j)));
    }
  }
  return Math.sqrt(Math.max(0, sigma2 * total));
}
function projectionVariance(fit2, design, u, phi) {
  const { rows: X, times } = design;
  if (u.length !== fit2.n) {
    throw new RangeError("projectionVariance needs one weight per fitted row.");
  }
  const xtu = zeros(fit2.k);
  X.forEach((row, i) => {
    const ui = at(u, i);
    for (let c = 0; c < fit2.k; c++) {
      xtu[c] = at(xtu, c) + ui * at(row, c);
    }
  });
  const g = multiply(fit2.xtxInverse, xtu);
  const v = X.map((row, i) => at(u, i) - dot(row, g));
  const powers = phiPowers(times, phi);
  let total = 0;
  for (let i = 0; i < v.length; i++) {
    for (let j = 0; j < v.length; j++) {
      total += at(v, i) * at(v, j) * at(powers, Math.abs(at(times, i) - at(times, j)));
    }
  }
  return total;
}
var ACKLAM_A = [
  -39.69683028665376,
  220.9460984245205,
  -275.9285104469687,
  138.357751867269,
  -30.66479806614716,
  2.506628277459239
];
var ACKLAM_B = [
  -54.47609879822406,
  161.5858368580409,
  -155.6989798598866,
  66.80131188771972,
  -13.28068155288572
];
var ACKLAM_C = [
  -0.007784894002430293,
  -0.3223964580411365,
  -2.400758277161838,
  -2.549732539343734,
  4.374664141464968,
  2.938163982698783
];
var ACKLAM_D = [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416];
var ACKLAM_P_LOW = 0.02425;
function polynomial(coefficients, x) {
  let value = 0;
  for (const c of coefficients) {
    value = value * x + c;
  }
  return value;
}
function normalQuantile(p) {
  if (!(p > 0 && p < 1)) {
    throw new RangeError("normalQuantile needs p strictly between 0 and 1.");
  }
  if (p < ACKLAM_P_LOW) {
    const q2 = Math.sqrt(-2 * Math.log(p));
    return polynomial(ACKLAM_C, q2) / (polynomial(ACKLAM_D, q2) * q2 + 1);
  }
  if (p > 1 - ACKLAM_P_LOW) {
    const q2 = Math.sqrt(-2 * Math.log(1 - p));
    return -polynomial(ACKLAM_C, q2) / (polynomial(ACKLAM_D, q2) * q2 + 1);
  }
  const q = p - 0.5;
  const r = q * q;
  return polynomial(ACKLAM_A, r) * q / (polynomial(ACKLAM_B, r) * r + 1);
}
var LANCZOS_G = 7;
var LANCZOS = [
  0.9999999999998099,
  676.5203681218851,
  -1259.1392167224028,
  771.3234287776531,
  -176.6150291621406,
  12.507343278686905,
  -0.13857109526572012,
  9984369578019572e-21,
  15056327351493116e-23
];
var BETA_MAX_ITERATIONS = 300;
var BETA_TOLERANCE = 3e-14;
var BETA_TINY = 1e-300;
function lgamma(x) {
  if (x < 0.5) {
    return Math.log(Math.PI / Math.sin(Math.PI * x)) - lgamma(1 - x);
  }
  const y = x - 1;
  let a = at(LANCZOS, 0);
  const t = y + LANCZOS_G + 0.5;
  for (let i = 1; i < LANCZOS.length; i++) {
    a += at(LANCZOS, i) / (y + i);
  }
  return 0.5 * Math.log(2 * Math.PI) + (y + 0.5) * Math.log(t) - t + Math.log(a);
}
function betaContinuedFraction(a, b, x) {
  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let c = 1;
  let d = 1 - qab * x / qap;
  if (Math.abs(d) < BETA_TINY) d = BETA_TINY;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= BETA_MAX_ITERATIONS; m++) {
    const m2 = 2 * m;
    let aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < BETA_TINY) d = BETA_TINY;
    c = 1 + aa / c;
    if (Math.abs(c) < BETA_TINY) c = BETA_TINY;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < BETA_TINY) d = BETA_TINY;
    c = 1 + aa / c;
    if (Math.abs(c) < BETA_TINY) c = BETA_TINY;
    d = 1 / d;
    const delta = d * c;
    h *= delta;
    if (Math.abs(delta - 1) < BETA_TOLERANCE) break;
  }
  return h;
}
function regularizedBeta(x, a, b) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const front = Math.exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * Math.log(x) + b * Math.log(1 - x));
  if (x < (a + 1) / (a + b + 2)) {
    return front * betaContinuedFraction(a, b, x) / a;
  }
  return 1 - front * betaContinuedFraction(b, a, 1 - x) / b;
}
function tCdf(x, df) {
  if (!(df > 0)) {
    throw new RangeError("tCdf needs positive degrees of freedom.");
  }
  const z = df / (df + x * x);
  const tail = 0.5 * regularizedBeta(z, df / 2, 0.5);
  return x >= 0 ? 1 - tail : tail;
}
var T_QUANTILE_BOUND = 100;
var T_QUANTILE_WIDTH = 1e-10;
var T_QUANTILE_STEPS = 200;
var T_NORMAL_DF = 1e3;
function tQuantile(p, df) {
  if (!(p > 0 && p < 1)) {
    throw new RangeError("tQuantile needs p strictly between 0 and 1.");
  }
  if (!(df > 0)) {
    throw new RangeError("tQuantile needs positive degrees of freedom.");
  }
  if (df > T_NORMAL_DF) {
    return normalQuantile(p);
  }
  let lo = -T_QUANTILE_BOUND;
  let hi = T_QUANTILE_BOUND;
  for (let step2 = 0; step2 < T_QUANTILE_STEPS && hi - lo >= T_QUANTILE_WIDTH; step2++) {
    const mid = (lo + hi) / 2;
    if (tCdf(mid, df) < p) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

// src/engine/its.ts
var LEVERAGE_FLOOR = 1e-12;
var NO_DROP = /* @__PURE__ */ new Set();
function at3(xs, i) {
  return xs[i];
}
function cell(m, i, j) {
  return at3(m[i], j);
}
function zeros2(n) {
  return new Array(n).fill(0);
}
function dot2(a, b) {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    s += at3(a, i) * at3(b, i);
  }
  return s;
}
function quadraticForm(V, a) {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    for (let j = 0; j < a.length; j++) {
      s += at3(a, i) * cell(V, i, j) * at3(a, j);
    }
  }
  return s;
}
function criticalT(df) {
  return tQuantile(1 - (1 - CONFIDENCE) / 2, df);
}
function presentRows(values, from, to, drop = NO_DROP) {
  const times = [];
  const kept = [];
  const last = Math.min(to, values.length - 1);
  for (let t = Math.max(0, from); t <= last; t++) {
    const v = values[t];
    if (v === null || v === void 0 || drop.has(t)) continue;
    times.push(t);
    kept.push(v);
  }
  return { times, values: kept };
}
function seasonalCount(season) {
  return season === null ? 0 : 2 * season.harmonics;
}
function seasonalColumns(t, season) {
  if (season === null) return [];
  const columns = [];
  for (let k = 1; k <= season.harmonics; k++) {
    const angle = 2 * Math.PI * k * t / season.period;
    columns.push(Math.sin(angle), Math.cos(angle));
  }
  return columns;
}
function seasonalTerms(frequency, nPre, nPost) {
  if (frequency !== "weekly" && frequency !== "monthly") {
    return { season: null, seasonality: "not-applicable", period: null, shortfall: null };
  }
  const period = SEASON_PERIOD[frequency];
  const harmonics = SEASON_HARMONICS[period];
  if (nPre < period) {
    return { season: null, seasonality: "not-ruled-out", period, shortfall: "pre-under-one-cycle" };
  }
  if (nPre + nPost < 2 * period) {
    return { season: null, seasonality: "not-ruled-out", period, shortfall: "under-two-cycles" };
  }
  return { season: { period, harmonics }, seasonality: "adjusted", period, shortfall: null };
}
function itsRow(t, Tb, season) {
  const u = t - Tb;
  const post = t >= Tb;
  return [1, u, post ? 1 : 0, post ? u : 0, ...seasonalColumns(t, season)];
}
function itsDesign(times, Tb, season) {
  return times.map((t) => itsRow(t, Tb, season));
}
function preRow(t, Tb, season) {
  return [1, t - Tb, ...seasonalColumns(t, season)];
}
function preDesign(times, Tb, season) {
  return times.map((t) => preRow(t, Tb, season));
}
function projectionRow(t, Tb, season) {
  return [1, t - Tb, 0, 0, ...seasonalColumns(t, season)];
}
function influenceRows(fit2, design, weights, sigma2) {
  return design.times.map((t, i) => {
    const e = at3(fit2.residuals, i);
    const slack = 1 - at3(fit2.hat, i);
    const weight = weights.get(t) ?? 0;
    if (slack <= LEVERAGE_FLOOR || sigma2 <= 0) {
      return { index: t, weight, delta: 0, standardizedResidual: 0 };
    }
    return {
      index: t,
      weight,
      delta: -weight * e / slack,
      standardizedResidual: e / Math.sqrt(sigma2 * slack)
    };
  });
}
function fitIts(values, T0, L, W, season, drop = NO_DROP) {
  const Tb = T0 + L;
  const pre = presentRows(values, 0, T0 - 1, drop);
  const post = presentRows(values, Tb, Tb + W - 1, drop);
  const seasonal = seasonalCount(season);
  if (pre.times.length < 2 + seasonal || post.times.length < 2) {
    return null;
  }
  const times = [...pre.times, ...post.times];
  const y = [...pre.values, ...post.values];
  const k = 4 + seasonal;
  if (times.length <= k) {
    return null;
  }
  const rows = itsDesign(times, Tb, season);
  const fit2 = ols(rows, y);
  const design = { rows, times };
  const uBar = mean(post.times.map((t) => t - Tb));
  const contrast = zeros2(k);
  contrast[2] = 1;
  contrast[3] = uBar;
  const phi = ar1Coefficient(fit2, design);
  const { V, sigma2 } = ar1Covariance(fit2, design, phi);
  const { estimate: effect, se } = linearCombination(fit2, V, contrast);
  const df = effectiveDf(fit2.df, phi);
  const tCrit = criticalT(df);
  const weights = effectWeights(fit2, design, contrast);
  const slopeSe = Math.sqrt(Math.max(0, cell(V, 1, 1)));
  const preSlope = at3(fit2.beta, 1);
  return {
    T0,
    Tb,
    W,
    season,
    design,
    ols: fit2,
    preRows: pre.times.length,
    windowRows: post.times.length,
    contrast,
    effect,
    standardError: se,
    interval: { lower: effect - tCrit * se, upper: effect + tCrit * se, level: CONFIDENCE },
    degreesOfFreedom: fit2.df,
    effectiveDegreesOfFreedom: df,
    phi,
    sigma2,
    covariance: V,
    levelChange: at3(fit2.beta, 2),
    trendChange: at3(fit2.beta, 3),
    preSlope,
    preSlopeT: slopeSe > 0 ? preSlope / slopeSe : 0,
    weights,
    influence: influenceRows(fit2, design, weights, sigma2)
  };
}
function trendLine(its2, t) {
  return at3(its2.ols.beta, 0) + at3(its2.ols.beta, 1) * (t - its2.Tb);
}
function seasonalPart(its2, t) {
  const columns = seasonalColumns(t, its2.season);
  let s = 0;
  for (let j = 0; j < columns.length; j++) {
    s += at3(columns, j) * at3(its2.ols.beta, 4 + j);
  }
  return s;
}
function intervalMethodSentence(phi, df) {
  return `Interval from a segmented regression with standard errors from an AR(1) noise model fitted to the residuals (coefficient ${formatCoefficient(phi)}), ` + degreesClause(phi, df);
}
function degreesClause(phi, df) {
  if (phi <= 0) {
    return `t critical value with ${formatCount(df)} degrees of freedom.`;
  }
  const scaled = formatFixed(effectiveDf(df, phi), 1);
  return `t critical value with ${scaled} degrees of freedom (the fit's ${formatCount(df)} residual degrees of freedom scaled by (1 - ${formatCoefficient(phi)}) / (1 + ${formatCoefficient(phi)}) for the autocorrelation).`;
}
function fitPre(values, T0, Tb, season) {
  const pre = presentRows(values, 0, T0 - 1);
  const k = 2 + seasonalCount(season);
  if (pre.times.length <= k) {
    return null;
  }
  const rows = preDesign(pre.times, Tb, season);
  const fit2 = ols(rows, pre.values);
  const design = { rows, times: pre.times };
  const noiseSd = Math.sqrt(fit2.rss / fit2.df);
  const phi = ar1Coefficient(fit2, design);
  const residuals = /* @__PURE__ */ new Map();
  values.forEach((v, t) => {
    if (v === null) return;
    residuals.set(t, v - dot2(preRow(t, Tb, season), fit2.beta));
  });
  return { T0, Tb, season, design, ols: fit2, noiseSd, phi, residuals };
}
function bendTest(times, values, T0, season) {
  const mid = Math.floor(T0 / 2);
  if (!times.some((t) => t < mid) || !times.some((t) => t > mid)) {
    return 0;
  }
  const k = 3 + seasonalCount(season);
  if (times.length <= k) {
    return 0;
  }
  const rows = times.map((t) => [1, t, Math.max(0, t - mid), ...seasonalColumns(t, season)]);
  const fit2 = ols(rows, values);
  const design = { rows, times };
  const phi = ar1Coefficient(fit2, design);
  const { V } = ar1Covariance(fit2, design, phi);
  const se = Math.sqrt(Math.max(0, cell(V, 2, 2)));
  return se > 0 ? at3(fit2.beta, 2) / se : 0;
}
function tailWeights(n, m) {
  const count = Math.min(m, n);
  const u = zeros2(n);
  for (let i = n - count; i < n; i++) {
    u[i] = 1 / count;
  }
  return u;
}
function tailTest(fit2, design, noiseSd, phi, m) {
  const u = tailWeights(fit2.n, m);
  const tailMean = dot2(u, fit2.residuals);
  const factor = projectionVariance(fit2, design, u, phi);
  const denominator = noiseSd * Math.sqrt(Math.max(0, factor));
  return denominator > 0 ? tailMean / denominator : 0;
}
function tailGap(pre, m) {
  return dot2(tailWeights(pre.ols.n, m), pre.ols.residuals);
}
function stability(bendT, tailZ, tailPeriods) {
  return {
    bendT,
    tailZ,
    tailPeriods,
    stable: Math.abs(bendT) < T_BEND && Math.abs(tailZ) < Z_TAIL
  };
}
function preTrendStability(values, T0, pre) {
  const rows = presentRows(values, 0, T0 - 1);
  const bendT = bendTest(rows.times, rows.values, T0, pre.season);
  const m = TAIL_PERIODS(rows.times.length);
  const tailZ = tailTest(pre.ols, pre.design, pre.noiseSd, pre.phi, m);
  return stability(bendT, tailZ, m);
}
function itsLines(its2, n) {
  const { T0, Tb, W, season, covariance } = its2;
  const beta = its2.ols.beta;
  const tCrit = criticalT(its2.effectiveDegreesOfFreedom);
  const preTrend = [];
  const preTrendLower = [];
  const preTrendUpper = [];
  const postFit = [];
  for (let t = 0; t < n; t++) {
    const a = projectionRow(t, Tb, season);
    const p = dot2(a, beta);
    preTrend.push(p);
    if (t >= T0) {
      const hw = tCrit * Math.sqrt(Math.max(0, quadraticForm(covariance, a)));
      preTrendLower.push(p - hw);
      preTrendUpper.push(p + hw);
    } else {
      preTrendLower.push(null);
      preTrendUpper.push(null);
    }
    postFit.push(t >= Tb && t <= Tb + W - 1 ? dot2(itsRow(t, Tb, season), beta) : null);
  }
  return { preTrend, preTrendLower, preTrendUpper, postFit };
}
function percentUnitsAvailable2(preValues2) {
  if (preValues2.length === 0) {
    return false;
  }
  return percentUnitsAvailable(mean(preValues2), preValues2.length >= 2 ? sd(preValues2) : 0);
}
function its(values, T0, L, W, frequency) {
  const Tb = T0 + L;
  const pre = presentRows(values, 0, T0 - 1);
  const window = presentRows(values, Tb, Tb + W - 1);
  const nPre = pre.times.length;
  const nPost = window.times.length;
  if (nPre < MIN_PRE || nPost < MIN_POST) {
    return null;
  }
  const decision = seasonalTerms(frequency, nPre, nPost);
  const fit2 = fitIts(values, T0, L, W, decision.season);
  const preFit = fitPre(values, T0, Tb, decision.season);
  if (fit2 === null || preFit === null) {
    return null;
  }
  const preTrend = preTrendStability(values, T0, preFit);
  const preMean = mean(pre.values);
  const percent = percentUnitsAvailable2(pre.values);
  const estimate = {
    method: "its",
    effect: fit2.effect,
    standardError: fit2.standardError,
    interval: fit2.interval,
    effectPercent: percent ? fit2.effect / preMean : null,
    intervalPercent: percent ? {
      lower: fit2.interval.lower / preMean,
      upper: fit2.interval.upper / preMean,
      level: CONFIDENCE
    } : null,
    degreesOfFreedom: fit2.degreesOfFreedom,
    effectiveDegreesOfFreedom: fit2.effectiveDegreesOfFreedom,
    fittedRows: fit2.ols.n,
    ar1: fit2.phi,
    noiseSd: preFit.noiseSd,
    levelChange: fit2.levelChange,
    trendChange: fit2.trendChange,
    preSlope: fit2.preSlope,
    preSlopeT: fit2.preSlopeT,
    seasonality: decision.seasonality,
    seasonalPeriod: decision.period,
    harmonics: decision.season === null ? 0 : decision.season.harmonics,
    intervalMethod: intervalMethodSentence(fit2.phi, fit2.degreesOfFreedom),
    preTrend,
    parallelTrends: null
  };
  return { estimate, fit: fit2, pre: preFit, lines: itsLines(fit2, values.length) };
}

// src/engine/words.ts
var MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
];
var ISO_DATE2 = /^(\d{4})-(\d{2})-(\d{2})$/;
function unit(frequency, count) {
  const singular = unitWord(frequency);
  if (count === void 0 || count === 1) {
    return singular;
  }
  return `${singular}s`;
}
function unitWord(frequency) {
  switch (frequency) {
    case "weekly":
      return "week";
    case "monthly":
      return "month";
    case "daily":
      return "day";
    case "unknown":
      return "period";
  }
}
function cycleWord(frequency) {
  switch (frequency) {
    case "weekly":
    case "monthly":
    case "daily":
      return "year";
    case "unknown":
      return "cycle";
  }
}
function name(series, question) {
  const metric = question?.metricName?.trim();
  if (metric) {
    return metric;
  }
  const header = series?.name?.trim();
  if (header) {
    return header;
  }
  return "the number";
}
function Name(series, question) {
  const text = name(series, question);
  return text.charAt(0).toUpperCase() + text.slice(1);
}
var SINGULAR_IN_S = /* @__PURE__ */ new Set(["news", "series", "species", "analytics"]);
function plural2(metricName) {
  const words = metricName.trim().split(/\s+/);
  const last = (words[words.length - 1] ?? "").replace(/[^A-Za-z0-9]+$/, "");
  if (last.length < 2 || !/s$/i.test(last)) {
    return false;
  }
  if (/^[A-Z0-9]+$/.test(last)) {
    return false;
  }
  if (/(ss|us|is)$/.test(last)) {
    return false;
  }
  return !SINGULAR_IN_S.has(last.toLowerCase());
}
function agree(metricName, singular, pluralForm) {
  return plural2(metricName) ? pluralForm : singular;
}
function dates(periods, frequency) {
  const list = isPeriodList(periods) ? periods : [periods];
  const words = list.map((period) => dateWord(period, frequency));
  if (words.length <= 1) {
    return words[0] ?? "";
  }
  if (words.length === 2) {
    return `${words[0]} and ${words[1]}`;
  }
  const last = words[words.length - 1];
  return `${words.slice(0, -1).join(", ")}, and ${last}`;
}
function isPeriodList(periods) {
  return Array.isArray(periods);
}
function dateWord(period, frequency) {
  if (period.date === null) {
    return `${unit(frequency)} ${period.index + 1}`;
  }
  const match = ISO_DATE2.exec(period.date);
  if (match === null) {
    return period.date;
  }
  const year = match[1];
  const monthIndex = Number(match[2]) - 1;
  const day = Number(match[3]);
  const month = MONTHS[monthIndex];
  if (month === void 0 || year === void 0 || !Number.isFinite(day) || day < 1) {
    return period.date;
  }
  if (frequency === "monthly") {
    return `${month} ${year}`;
  }
  return `${month} ${day}, ${year}`;
}
function baseline(method, metricName = "") {
  switch (method) {
    case "its":
      return `${agree(metricName, "its", "their")} pre trend`;
    case "did":
      return "the comparison group";
  }
}

// src/engine/alternatives.ts
var KINDS = ["trend", "seasonal", "outliers", "return", "control"];
var NO_HISTORY_SENTENCE = "No alternative explanation could be tested with this little history.";
var NONE_ACCOUNTS_SENTENCE = "None of the explanations the data can test accounts for the move.";
var NO_CONTROL_SENTENCE = "No comparison group was given.";
var CONTROL_UNUSABLE_SENTENCE = "The comparison group had too few values beside the treated series to be tested.";
var NO_CYCLE_SENTENCE = "No seasonal cycle is defined for this series.";
var OUTLIER_CHECK_ABSENT_SENTENCE = "The outlier check did not run, so no unusual period could be tested.";
function sign(x) {
  return x > 0 ? 1 : x < 0 ? -1 : 0;
}
function clip01(x) {
  if (!Number.isFinite(x)) return 0;
  return Math.min(1, Math.max(0, x));
}
function criticalT2(df) {
  return tQuantile(1 - (1 - CONFIDENCE) / 2, df);
}
function includesZero(interval, mAbs, noiseSd) {
  const { effect } = effectReading(interval.lower, interval.upper, mAbs, noiseSd);
  return effect === "uncertain" || effect === "near-zero";
}
function untested(kind, reason) {
  return {
    kind,
    assessable: false,
    untestedReason: reason,
    strength: 0,
    detected: false,
    explainsAsWell: false,
    sentence: reason
  };
}
function assessed(kind, strength, detected, explainsAsWell, sentence) {
  return { kind, assessable: true, untestedReason: null, strength, detected, explainsAsWell, sentence };
}
function periodAt(series, index) {
  return series.periods[index] ?? { index, date: null, value: null };
}
function context(input, its2, headline2) {
  const values = input.series.periods.map((p) => p.value);
  const times = its2.fit.design.times;
  const preTimes = times.filter((t) => t < its2.fit.T0);
  const windowTimes = times.filter((t) => t >= its2.fit.Tb);
  const naive = input.descriptive?.absoluteChange ?? 0;
  const preMean = input.descriptive?.preMean ?? mean(preTimes.map((t) => values[t]));
  return {
    input,
    its: its2,
    headline: headline2,
    values,
    frequency: input.series.frequency,
    style: { unit: input.series.unit, currencySymbol: input.series.currencySymbol },
    naive,
    shareDefined: naive !== 0 && Math.abs(naive) >= NAIVE_FLOOR * input.noiseSd,
    headlineIncludesZero: includesZero(headline2.interval, input.mAbs, input.noiseSd),
    preTimes,
    windowTimes,
    preMean
  };
}
function trendPart(fit2, c) {
  return mean(c.windowTimes.map((t) => trendLine(fit2, t))) - mean(c.preTimes.map((t) => trendLine(fit2, t)));
}
function trendCandidate(c) {
  const fit2 = c.its.fit;
  const established = Math.abs(fit2.preSlopeT) >= T_SLOPE;
  const strength = established && c.shareDefined ? clip01(sign(c.naive) * trendPart(fit2, c) / Math.abs(c.naive)) : 0;
  const detected = strength >= ALT_EXPLAINS;
  const explainsAsWell = detected && c.headlineIncludesZero;
  const metric = Name(c.input.series, c.input.question);
  const was = agree(metric, "was", "were");
  if (!established) {
    return assessed(
      "trend",
      strength,
      detected,
      explainsAsWell,
      `${metric} ${was} flat before the change; no trend accounts for the before-and-after move.`
    );
  }
  const slopeSe = Math.sqrt(Math.max(0, fit2.covariance[1]?.[1] ?? 0));
  const slope = formatAbsolute(Math.abs(fit2.preSlope), criticalT2(fit2.effectiveDegreesOfFreedom) * slopeSe, c.style);
  return assessed(
    "trend",
    strength,
    detected,
    explainsAsWell,
    `${metric} ${was} already ${fit2.preSlope > 0 ? "rising" : "falling"} about ${slope} per ${unit(c.frequency)} before the change; that trend accounts for ${formatShare(strength)} of the before-and-after move.`
  );
}
function seasonalPeriodOf(frequency) {
  if (frequency === "weekly" || frequency === "monthly") {
    return SEASON_PERIOD[frequency];
  }
  return null;
}
function seasonalLineup(values, T0, Tb, W, S) {
  const lineup = [];
  const last = Math.min(Tb + W - 1, values.length - 1);
  for (let t = Tb; t <= last; t++) {
    const earlier = t - S;
    if (earlier < 0 || earlier >= T0) continue;
    if (values[t] == null || values[earlier] == null) continue;
    lineup.push(t);
  }
  return lineup;
}
function counterpartMove(values, lineup, S, preMean) {
  return mean(lineup.map((t) => values[t - S] - preMean));
}
function seasonalShortfallSentence(frequency, nPre, nPost, S) {
  if (nPre < S) {
    return `Seasonality could not be ruled out: ${formatCount(nPre)} ${unit(frequency, nPre)} before the change, ${formatCount(S)} needed to see every phase before it.`;
  }
  const rows = nPre + nPost;
  return `Seasonality could not be ruled out: ${formatCount(rows)} ${unit(frequency, rows)} went into the fit, and ${formatCount(2 * S)} are needed.`;
}
function adjustedSeasonalCandidate(c) {
  const fit2 = c.its.fit;
  const part = mean(c.windowTimes.map((t) => seasonalPart(fit2, t))) - mean(c.preTimes.map((t) => seasonalPart(fit2, t)));
  const strength = c.shareDefined ? clip01(sign(c.naive) * part / Math.abs(c.naive)) : 0;
  const detected = strength >= ALT_EXPLAINS;
  return assessed(
    "seasonal",
    strength,
    detected,
    detected && c.headlineIncludesZero,
    `The post period is a seasonal ${part >= 0 ? "high" : "low"}; after adjustment the seasonal pattern accounts for ${formatShare(strength)} of the before-and-after move.`
  );
}
function lineupSeasonalCandidate(c, S) {
  const fit2 = c.its.fit;
  const lineup = seasonalLineup(c.values, fit2.T0, fit2.Tb, fit2.W, S);
  if (lineup.length < SEASON_LINEUP_MIN) {
    return untested("seasonal", seasonalShortfallSentence(c.frequency, fit2.preRows, fit2.windowRows, S));
  }
  const cp = counterpartMove(c.values, lineup, S, c.preMean);
  const strength = c.shareDefined && sign(cp) === sign(c.naive) ? clip01(cp / c.naive) : 0;
  const detected = strength >= ALT_EXPLAINS;
  const explainsAsWell = detected && (c.headline.method === "its" || c.headlineIncludesZero);
  const size = formatAbsolute(Math.abs(cp), c.input.noiseSd / Math.sqrt(lineup.length), c.style);
  return assessed(
    "seasonal",
    strength,
    detected,
    explainsAsWell,
    `The same ${unit(c.frequency, 2)} one ${cycleWord(c.frequency)} earlier ran ${size} ${cp >= 0 ? "above" : "below"} the pre-period average, which matches ${formatShare(strength)} of the before-and-after move; seasonality could not be adjusted with less than two full cycles.`
  );
}
function seasonalCandidate(c) {
  if (c.its.fit.season !== null) {
    return adjustedSeasonalCandidate(c);
  }
  const S = seasonalPeriodOf(c.frequency);
  if (S === null) {
    return untested("seasonal", NO_CYCLE_SENTENCE);
  }
  return lineupSeasonalCandidate(c, S);
}
function outliersCandidate(c) {
  const check = c.input.outliers;
  if (check === null) {
    return untested("outliers", OUTLIER_CHECK_ABSENT_SENTENCE);
  }
  const E = c.headline.effect;
  const sE = sign(E);
  const one = sE * check.effectWithoutOne;
  const two = sE * check.effectWithoutTwo;
  const twoIsSmaller = two < one;
  const eMin = twoIsSmaller ? two : one;
  const strength = c.headlineIncludesZero ? 0 : clip01(1 - eMin / Math.abs(E));
  const detected = strength >= ALT_EXPLAINS && check.status === "sensitive";
  const dropped = twoIsSmaller ? [check.dropped[0], check.dropped[1]] : [check.dropped[0]];
  const named = dates(
    dropped.map((index) => periodAt(c.input.series, index)),
    c.frequency
  );
  return assessed(
    "outliers",
    strength,
    detected,
    detected,
    `Dropping ${named} removes ${formatShare(strength)} of the effect.`
  );
}
function returnCandidate(c) {
  const { fit: fit2, pre } = c.its;
  const m = TAIL_PERIODS(c.preTimes.length);
  const tail = new Set(c.preTimes.slice(-m));
  const refit2 = fitIts(c.values, fit2.T0, fit2.Tb - fit2.T0, fit2.W, fit2.season, tail);
  const unitWord3 = unit(c.frequency, m);
  if (refit2 === null) {
    return untested(
      "return",
      `Too few ${unit(c.frequency, 2)} before the change remain once the last ${formatCount(m)} are set aside.`
    );
  }
  const E = fit2.effect;
  const sE = sign(E);
  const directional = !includesZero(fit2.interval, c.input.mAbs, c.input.noiseSd);
  const dSe = differenceSe(fit2.weights, refit2.weights, fit2.phi, fit2.sigma2);
  const triggered = directional && sE * (E - refit2.effect) > ROBUST_Z * dSe;
  const strength = triggered ? clip01(1 - sE * refit2.effect / Math.abs(E)) : 0;
  const detected = strength >= ALT_EXPLAINS;
  const explainsAsWell = detected && includesZero(refit2.interval, c.input.mAbs, c.input.noiseSd);
  const gap = tailGap(pre, m);
  const size = formatAbsolute(Math.abs(gap), c.input.noiseSd / Math.sqrt(m), c.style);
  const side = gap < 0 ? "below" : "above";
  const opening = `The last ${formatCount(m)} ${unitWord3} before the change ran ${size} ${side} trend`;
  const sentence = triggered ? `${opening}; measured against the trend without them, ${formatShare(strength)} of the effect disappears.` : `${opening}; the effect does not rest on them.`;
  return assessed("return", strength, detected, explainsAsWell, sentence);
}
function controlCandidate(c) {
  const control = c.input.series.control;
  if (control === null) {
    return untested("control", NO_CONTROL_SENTENCE);
  }
  if (c.headline.method !== "did") {
    return untested("control", CONTROL_UNUSABLE_SENTENCE);
  }
  const fit2 = c.its.fit;
  const controlFit = fitIts(
    control.map((p) => p.value),
    fit2.T0,
    fit2.Tb - fit2.T0,
    fit2.W,
    fit2.season
  );
  if (controlFit === null) {
    return untested("control", CONTROL_UNUSABLE_SENTENCE);
  }
  const Ec = controlFit.effect;
  const Eits = fit2.effect;
  const treatedExcludesZero = !includesZero(fit2.interval, c.input.mAbs, c.input.noiseSd);
  const strength = treatedExcludesZero && Eits !== 0 && sign(Ec) === sign(Eits) ? clip01(Ec / Eits) : 0;
  const detected = strength >= ALT_EXPLAINS;
  const moved = formatAbsolute(Ec, halfWidth(controlFit.interval), c.style);
  return assessed(
    "control",
    strength,
    detected,
    detected && c.headlineIncludesZero,
    `The comparison group moved ${moved} over the same window, ${formatShare(strength)} of the treated group's move.`
  );
}
function strongestOf(candidates) {
  let best = null;
  for (const candidate of candidates) {
    if (best === null || candidate.strength > best.strength) {
      best = candidate;
    }
  }
  return best;
}
function alternatives(input) {
  if (input.its === null || input.estimate === null) {
    return {
      strongest: null,
      explainsAsWell: false,
      explainedBy: null,
      candidates: KINDS.map((kind) => untested(kind, NO_HISTORY_SENTENCE)),
      sentence: NO_HISTORY_SENTENCE
    };
  }
  const c = context(input, input.its, input.estimate);
  const candidates = [
    trendCandidate(c),
    seasonalCandidate(c),
    outliersCandidate(c),
    returnCandidate(c),
    controlCandidate(c)
  ];
  const strongest = strongestOf(candidates.filter((a) => a.assessable));
  const explaining = strongestOf(candidates.filter((a) => a.explainsAsWell));
  const sentence = strongest === null || strongest.strength <= 0 ? NONE_ACCOUNTS_SENTENCE : strongest.sentence;
  return {
    strongest,
    explainsAsWell: explaining !== null,
    explainedBy: explaining === null ? null : explaining.kind,
    candidates,
    sentence
  };
}

// src/engine/beforeAfter.ts
var MIN_PRESENT_PRE = 2;
var MIN_PRESENT_POST = 1;
function present(values, first, last) {
  const out = [];
  const stop = Math.min(last, values.length - 1);
  for (let t = Math.max(0, first); t <= stop; t++) {
    const v = values[t];
    if (v !== null && v !== void 0) {
      out.push(v);
    }
  }
  return out;
}
function percentUnitsAvailable3(preValues2) {
  return percentUnitsAvailable(mean(preValues2), sd(preValues2));
}
function beforeAfter(values, question, window) {
  const changeIndex = question.changeIndex;
  const tb = changeIndex + (question.lagPeriods ?? 0);
  const preValues2 = present(values, 0, changeIndex - 1);
  const windowValues = present(values, tb, tb + window.length - 1);
  if (preValues2.length < MIN_PRESENT_PRE || windowValues.length < MIN_PRESENT_POST) {
    return null;
  }
  const postAllValues = present(values, tb, values.length - 1);
  const preMean = mean(preValues2);
  const postMean = mean(windowValues);
  const absoluteChange = postMean - preMean;
  return {
    preMean,
    postMean,
    postMeanAll: mean(postAllValues),
    absoluteChange,
    percentChange: percentUnitsAvailable3(preValues2) ? absoluteChange / preMean : null,
    prePeriods: preValues2.length,
    postPeriods: windowValues.length
  };
}

// src/engine/chart.ts
function buildChart(series, question, lines, difference, placebo2, effectInterval) {
  const changeIndex = question.changeIndex;
  const evaluationStart = question.window.start;
  const evaluationEnd = evaluationStart + question.window.length - 1;
  const periods = series.periods.map(
    (period, position) => chartPeriod(
      period,
      series.control?.[position] ?? null,
      lines,
      difference,
      changeIndex,
      evaluationStart,
      evaluationEnd
    )
  );
  return {
    periods,
    changeIndex,
    evaluationStart,
    evaluationEnd,
    placebo: chartPlacebo(placebo2),
    effectInterval: copyInterval(effectInterval)
  };
}
function chartPeriod(period, control, lines, difference, changeIndex, evaluationStart, evaluationEnd) {
  const t = period.index;
  const fromChange = lines !== null && t >= changeIndex;
  const inWindow = lines !== null && t >= evaluationStart && t <= evaluationEnd;
  const controlValue = control === null ? null : control.value;
  return {
    index: t,
    date: period.date,
    value: period.value,
    preTrend: lines === null ? null : at4(lines.preTrend, t),
    preTrendLower: fromChange ? at4(lines.preTrendLower, t) : null,
    preTrendUpper: fromChange ? at4(lines.preTrendUpper, t) : null,
    postFit: inWindow ? at4(lines.postFit, t) : null,
    control: controlValue,
    difference: differenceAt(difference, t, period.value, controlValue)
  };
}
function at4(line, t) {
  return line[t] ?? null;
}
function differenceAt(difference, t, value, control) {
  const given = difference === null ? null : at4(difference, t);
  if (given !== null) {
    return given;
  }
  if (value === null || control === null) {
    return null;
  }
  return value - control;
}
function chartPlacebo(placebo2) {
  if (placebo2 === null) {
    return null;
  }
  return {
    window: placebo2.window,
    positions: placebo2.distribution.map(copyPosition),
    real: placebo2.realStatistic,
    realGap: placebo2.realGap
  };
}
function copyPosition(position) {
  return { index: position.index, statistic: position.statistic, gap: position.gap };
}
function copyInterval(interval) {
  if (interval === null) {
    return null;
  }
  return { lower: interval.lower, upper: interval.upper, level: interval.level };
}

// src/engine/did.ts
var DID_CONTRAST = [0, 1];
var PRE_COLUMNS = 2;
var LEVERAGE_FLOOR2 = 1e-12;
var NO_DROP2 = /* @__PURE__ */ new Set();
function at5(xs, i) {
  return xs[i];
}
function cell2(m, i, j) {
  return at5(m[i], j);
}
function criticalT3(df) {
  return tQuantile(1 - (1 - CONFIDENCE) / 2, df);
}
function presentRows2(values, from, to, drop = NO_DROP2) {
  const times = [];
  const kept = [];
  const last = Math.min(to, values.length - 1);
  for (let t = Math.max(0, from); t <= last; t++) {
    const v = values[t];
    if (v === null || v === void 0 || drop.has(t)) continue;
    times.push(t);
    kept.push(v);
  }
  return { times, values: kept };
}
function differenceSeries(treated, control) {
  return treated.map((y, t) => {
    const c = control[t];
    if (y === null || c === null || c === void 0) return null;
    return y - c;
  });
}
function controlUsability(difference, T0, Tb, W, frequency) {
  const preRows = presentRows2(difference, 0, T0 - 1).times.length;
  const windowRows = presentRows2(difference, Tb, Tb + W - 1).times.length;
  let fallback = null;
  if (preRows < MIN_PRE) {
    fallback = `The comparison group has ${formatCount(preRows)} ${unit(frequency, preRows)} before the change; ${formatCount(MIN_PRE)} are needed.`;
  } else if (windowRows < MIN_POST) {
    fallback = `The comparison group has ${formatCount(windowRows)} ${unit(frequency, windowRows)} after the change; ${formatCount(MIN_POST)} are needed.`;
  }
  return { usable: fallback === null, preRows, windowRows, fallback };
}
function didDesign(times, Tb) {
  return times.map((t) => [1, t >= Tb ? 1 : 0]);
}
function didIntervalMethodSentence(phi, df) {
  return `Interval from the treated minus control series with standard errors from an AR(1) noise model fitted to the residuals (coefficient ${formatCoefficient(phi)}), ` + degreesClause(phi, df);
}
function influenceRows2(fit2, design, weights, sigma2) {
  return design.times.map((t, i) => {
    const e = at5(fit2.residuals, i);
    const slack = 1 - at5(fit2.hat, i);
    const weight = weights.get(t) ?? 0;
    if (slack <= LEVERAGE_FLOOR2 || sigma2 <= 0) {
      return { index: t, weight, delta: 0, standardizedResidual: 0 };
    }
    return {
      index: t,
      weight,
      delta: -weight * e / slack,
      standardizedResidual: e / Math.sqrt(sigma2 * slack)
    };
  });
}
function fitDid(difference, T0, L, W, drop = NO_DROP2) {
  const Tb = T0 + L;
  const pre = presentRows2(difference, 0, T0 - 1, drop);
  const post = presentRows2(difference, Tb, Tb + W - 1, drop);
  if (pre.times.length < 2 || post.times.length < 2) {
    return null;
  }
  const times = [...pre.times, ...post.times];
  const d = [...pre.values, ...post.values];
  const rows = didDesign(times, Tb);
  const fit2 = ols(rows, d);
  const design = { rows, times };
  const contrast = [...DID_CONTRAST];
  const phi = ar1Coefficient(fit2, design);
  const { V, sigma2 } = ar1Covariance(fit2, design, phi);
  const { estimate: effect, se } = linearCombination(fit2, V, contrast);
  const df = effectiveDf(fit2.df, phi);
  const tCrit = criticalT3(df);
  const weights = effectWeights(fit2, design, contrast);
  return {
    T0,
    Tb,
    W,
    design,
    ols: fit2,
    preRows: pre.times.length,
    windowRows: post.times.length,
    contrast,
    effect,
    standardError: se,
    interval: { lower: effect - tCrit * se, upper: effect + tCrit * se, level: CONFIDENCE },
    degreesOfFreedom: fit2.df,
    effectiveDegreesOfFreedom: df,
    phi,
    sigma2,
    covariance: V,
    preMean: mean(pre.values),
    windowMean: mean(post.values),
    weights,
    influence: influenceRows2(fit2, design, weights, sigma2)
  };
}
function differencePreDesign(times, T0) {
  return times.map((t) => [1, t - (T0 - 1)]);
}
function fitDifferencePre(difference, T0) {
  const pre = presentRows2(difference, 0, T0 - 1);
  if (pre.times.length <= PRE_COLUMNS) {
    return null;
  }
  const rows = differencePreDesign(pre.times, T0);
  const fit2 = ols(rows, pre.values);
  const design = { rows, times: pre.times };
  const noiseSd = Math.sqrt(fit2.rss / fit2.df);
  const phi = ar1Coefficient(fit2, design);
  const { V } = ar1Covariance(fit2, design, phi);
  const slope = at5(fit2.beta, 1);
  const slopeSe = Math.sqrt(Math.max(0, cell2(V, 1, 1)));
  return {
    T0,
    design,
    ols: fit2,
    noiseSd,
    phi,
    slope,
    slopeSe,
    slopeT: slopeSe > 0 ? slope / slopeSe : 0
  };
}
function horizon(T0, Tb, W) {
  return Tb + (W - 1) / 2 - (T0 - 1) / 2;
}
function judgeDivergence(inputs) {
  const { slope, slopeT, effect, halfWidth: hw, horizon: h } = inputs;
  const projectedDrift = Math.abs(slope) * h;
  const driftThreshold = hw / 2;
  const significantDrift = Math.abs(slopeT) >= T_SLOPE && projectedDrift >= driftThreshold;
  const driftAgainstEffect = Math.abs(effect) > hw && projectedDrift >= DRIFT_SHARE * Math.abs(effect);
  const rule = significantDrift ? "significant-drift" : driftAgainstEffect ? "drift-against-effect" : null;
  return { slope, slopeT, projectedDrift, driftThreshold, parallel: rule === null, rule };
}
function parallelTrends(pre, fit2) {
  return judgeDivergence({
    slope: pre.slope,
    slopeT: pre.slopeT,
    effect: fit2.effect,
    halfWidth: halfWidth(fit2.interval),
    horizon: horizon(fit2.T0, fit2.Tb, fit2.W)
  });
}
function divergenceSentence(parallel, nPre, didHalfWidth, frequency, style) {
  if (parallel.parallel) {
    return null;
  }
  const drift = formatAbsolute(parallel.projectedDrift, didHalfWidth, style);
  if (Math.abs(parallel.slopeT) >= T_SLOPE) {
    return `Before the change the treated and comparison groups were drifting apart by about ${drift} over a window this long, so the comparison carries less weight.`;
  }
  return `The ${formatCount(nPre)} ${unit(frequency, nPre)} before the change cannot rule out the treated and comparison groups drifting apart by about ${drift} over a window this long, so the comparison carries less weight.`;
}
function differenceStability(difference, T0, pre) {
  const rows = presentRows2(difference, 0, T0 - 1);
  const bendT = bendTest(rows.times, rows.values, T0, null);
  const m = TAIL_PERIODS(rows.times.length);
  const tailZ = tailTest(pre.ols, pre.design, pre.noiseSd, pre.phi, m);
  return stability(bendT, tailZ, m);
}
function did(treated, control, T0, L, W, frequency, style) {
  const Tb = T0 + L;
  const difference = differenceSeries(treated, control);
  if (!controlUsability(difference, T0, Tb, W, frequency).usable) {
    return null;
  }
  const fit2 = fitDid(difference, T0, L, W);
  const pre = fitDifferencePre(difference, T0);
  if (fit2 === null || pre === null) {
    return null;
  }
  const parallel = parallelTrends(pre, fit2);
  const preTrend = differenceStability(difference, T0, pre);
  const treatedPre = presentRows2(treated, 0, T0 - 1).values;
  const preMean = mean(treatedPre);
  const percent = percentUnitsAvailable2(treatedPre);
  const estimate = {
    method: "did",
    effect: fit2.effect,
    standardError: fit2.standardError,
    interval: fit2.interval,
    effectPercent: percent ? fit2.effect / preMean : null,
    intervalPercent: percent ? {
      lower: fit2.interval.lower / preMean,
      upper: fit2.interval.upper / preMean,
      level: CONFIDENCE
    } : null,
    degreesOfFreedom: fit2.degreesOfFreedom,
    effectiveDegreesOfFreedom: fit2.effectiveDegreesOfFreedom,
    fittedRows: fit2.ols.n,
    ar1: fit2.phi,
    noiseSd: pre.noiseSd,
    levelChange: null,
    trendChange: null,
    preSlope: null,
    preSlopeT: null,
    seasonality: "not-applicable",
    seasonalPeriod: null,
    harmonics: 0,
    intervalMethod: didIntervalMethodSentence(fit2.phi, fit2.degreesOfFreedom),
    preTrend,
    parallelTrends: parallel
  };
  return {
    estimate,
    fit: fit2,
    pre,
    difference,
    divergenceSentence: divergenceSentence(parallel, pre.ols.n, halfWidth(fit2.interval), frequency, style)
  };
}

// src/engine/dimensions.ts
var FIXED_SENTENCES = {
  "did-base": "A comparison group is present, so the effect is read as treated minus comparison.",
  "its-base": "No comparison group; the effect is read against the pre trend.",
  "before-after-only": "Only the before and after means could be computed.",
  "no-estimate": "Too little data to estimate anything beyond the means.",
  "pre-trend-unstable": "The pre trend bent or ended in a swing, so its projection is unreliable.",
  "seasonality-not-ruled-out": "Seasonality could not be ruled out on a monthly series, so a seasonal swing inside the window cannot be told from a step.",
  "placebo-not-assessed": "The placebo check could not run, so the reading stops at likely."
};
var DIVERGENCE_FALLBACK = "The pre period cannot vouch for parallel trends, so the comparison carries less weight.";
function resolveThreshold(question, preMean, preSd) {
  const minimum = question.minimumMeaningful ?? null;
  const target = question.target ?? null;
  const fraction = minimum ?? target;
  if (fraction !== null && preMean !== null && percentUnitsAvailable(preMean, preSd)) {
    return { mAbs: fraction * preMean, source: minimum !== null ? "minimumMeaningful" : "target" };
  }
  const absolute = question.minimumMeaningfulAbsolute ?? null;
  if (absolute !== null) {
    return { mAbs: absolute, source: "minimumMeaningfulAbsolute" };
  }
  return { mAbs: null, source: "none" };
}
function sufficiency(nPre, nPost, nPostAll) {
  if (nPostAll < MIN_POST) {
    return "too-early";
  }
  if (nPre < MIN_PRE) {
    return "low";
  }
  if (nPre >= GOOD_PRE && nPost >= GOOD_POST) {
    return "high";
  }
  return "medium";
}
function dimensions(input) {
  const { estimate, question, preMean, preSd, series } = input;
  const g = question.direction === "up" ? 1 : -1;
  const threshold = resolveThreshold(question, preMean, preSd);
  const effect = readEffect(estimate, threshold.mAbs);
  const trail = readIdentification(input);
  const size = readMateriality(estimate, g, question, threshold.mAbs, preMean, preSd);
  return {
    effect: effect.effect,
    effectBasis: effect.basis,
    identification: trail.reading,
    identificationSteps: trail.steps,
    preTrendStable: estimate?.preTrend.stable ?? true,
    materiality: size.materiality,
    thresholdState: size.thresholdState,
    targetState: size.targetState,
    materialityReason: size.materialityReason,
    sufficiency: sufficiency(series.prePresent, series.postPresent, series.postPresentAll),
    inStatedDirection: g > 0 && effect.effect === "positive" || g < 0 && effect.effect === "negative",
    oppositeDirection: g > 0 && effect.effect === "negative" || g < 0 && effect.effect === "positive"
  };
}
function readEffect(estimate, mAbs) {
  if (estimate === null) {
    return { effect: "uncertain", basis: "none" };
  }
  return effectReading(estimate.interval.lower, estimate.interval.upper, mAbs, estimate.noiseSd);
}
function readMateriality(estimate, g, question, mAbs, preMean, preSd) {
  if (estimate === null) {
    return {
      materiality: "not-assessed",
      thresholdState: "not-assessed",
      targetState: "none",
      materialityReason: "no-estimate"
    };
  }
  const { lower, upper } = estimate.interval;
  const state = thresholdState(lower, upper, g, mAbs);
  const targetState = readTarget(lower, upper, g, question.target ?? null, preMean, preSd);
  if (state === "not-assessed") {
    const fraction = question.minimumMeaningful ?? question.target ?? null;
    return {
      materiality: "not-assessed",
      thresholdState: state,
      targetState,
      materialityReason: fraction === null ? "no-threshold" : "pre-level-near-zero"
    };
  }
  return {
    materiality: state === "meets" ? "meaningful" : "below-threshold",
    thresholdState: state,
    targetState,
    materialityReason: null
  };
}
function readTarget(lower, upper, g, target, preMean, preSd) {
  if (target === null || preMean === null || !percentUnitsAvailable(preMean, preSd)) {
    return "none";
  }
  switch (thresholdState(lower, upper, g, target * preMean)) {
    case "meets":
      return "met";
    case "clearly-below":
      return "missed";
    case "possibly-below":
      return "not-settled";
    case "not-assessed":
      return "none";
  }
}
function readIdentification(input) {
  const { estimate, method, robustness: robustness2, placebo: placebo2 } = input;
  const nPre = input.series.prePresent;
  const frequency = input.series.frequency;
  const trail = { reading: "none", steps: [] };
  if (estimate === null) {
    if (method === "none") {
      base(trail, "no-estimate", "none");
    } else {
      base(trail, "before-after-only", "weak");
    }
  } else if (estimate.method === "its") {
    base(trail, "its-base", "moderate");
    if (nPre < GOOD_PRE) {
      step(trail, "short-history", "weak", shortHistorySentence(frequency), true);
    }
    if (!estimate.preTrend.stable) {
      step(trail, "pre-trend-unstable", "weak", FIXED_SENTENCES["pre-trend-unstable"], true);
    }
  } else {
    base(trail, "did-base", "strong");
    if (estimate.parallelTrends !== null && !estimate.parallelTrends.parallel) {
      step(trail, "pre-trends-diverge", "moderate", input.divergenceSentence ?? DIVERGENCE_FALLBACK);
    }
    if (nPre < GOOD_PRE) {
      step(trail, "short-history", oneStepDown(trail.reading), shortHistorySentence(frequency), true);
    }
    if (!estimate.preTrend.stable) {
      step(trail, "pre-trend-unstable", "weak", FIXED_SENTENCES["pre-trend-unstable"], true);
    }
  }
  if (robustness2 !== null) {
    if (robustness2.windows.status === "sensitive") {
      step(trail, "windows-sensitive", weakUnlessNone(trail.reading), robustness2.windows.sentence);
    }
    if (robustness2.outliers.status === "sensitive") {
      step(trail, "outliers-sensitive", weakUnlessNone(trail.reading), robustness2.outliers.sentence);
    }
  }
  if (estimate !== null && estimate.method === "its" && frequency === "monthly" && estimate.seasonality === "not-ruled-out") {
    step(trail, "seasonality-not-ruled-out", "weak", FIXED_SENTENCES["seasonality-not-ruled-out"]);
  }
  if (estimate !== null && estimate.ar1 >= AR1_LIMIT) {
    step(trail, "noise-model-at-limit", "weak", noiseModelSentence(estimate.ar1));
  }
  if (placebo2 === null || !placebo2.assessed) {
    step(trail, "placebo-not-assessed", capAtModerate(trail.reading), FIXED_SENTENCES["placebo-not-assessed"]);
  } else if (placebo2.atLeastAsLarge / placebo2.positions > PLACEBO_BULK) {
    step(
      trail,
      "placebo-in-bulk",
      oneStepDown(trail.reading),
      placeboBulkSentence(placebo2.atLeastAsLarge, placebo2.positions)
    );
  }
  return trail;
}
function base(trail, reason, reading) {
  trail.reading = reading;
  trail.steps.push({ reason, from: reading, to: reading, sentence: FIXED_SENTENCES[reason] });
}
function step(trail, reason, to, sentence, always = false) {
  if (always || to !== trail.reading) {
    trail.steps.push({ reason, from: trail.reading, to, sentence });
  }
  trail.reading = to;
}
function oneStepDown(reading) {
  switch (reading) {
    case "strong":
      return "moderate";
    case "moderate":
      return "weak";
    case "weak":
    case "none":
      return reading;
  }
}
function weakUnlessNone(reading) {
  return reading === "none" ? "none" : "weak";
}
function capAtModerate(reading) {
  return reading === "strong" ? "moderate" : reading;
}
function shortHistorySentence(frequency) {
  return `Fewer than ${formatCount(GOOD_PRE)} ${unit(frequency, GOOD_PRE)} before the change is a short baseline.`;
}
function noiseModelSentence(phi) {
  return `The series carries its previous value forward strongly (coefficient ${formatCoefficient(phi)}), where the interval runs too narrow to rate the cause.`;
}
function placeboBulkSentence(k, n) {
  return `A change this size showed up at ${formatCount(k)} of ${formatCount(n)} other dates, so the reading drops one step.`;
}

// src/engine/language.ts
var NO_ESTIMATE = "Can't tell: too little data to measure a change.";
var THRESHOLD_WORD = "threshold";
var UNSTABLE_SENTENCE = "The pre trend bent or ended in a swing, so its projection is unreliable.";
function causalClause(identification, observedSign, metric, size, measuredAgainst2) {
  const up = observedSign === "up";
  switch (identification) {
    case "strong":
      return up ? `The change caused a ${size} rise in ${metric}` : `The change caused a ${size} fall in ${metric}`;
    case "moderate":
      return up ? `The change likely raised ${metric} by ${size}` : `The change likely lowered ${metric} by ${size}`;
    case "weak":
    case "none": {
      const capitalized = Name(null, { metricName: metric });
      return up ? `${capitalized} ran ${size} above ${measuredAgainst2} after the change` : `${capitalized} ran ${size} below ${measuredAgainst2} after the change`;
    }
  }
}
function headline(input) {
  const c = context2(input);
  const { result: r } = c;
  switch (r.verdict.reason) {
    case "too-early":
      return tooEarly(c);
    case "no-estimate":
      return NO_ESTIMATE;
    case "before-after-only":
      return beforeAfterOnly(c);
    case "alternative-explains":
      return alternativeExplains(c);
    case "interval-includes-zero":
      return withEstimate(c, (m) => {
        const where = `${m.size} ${aboveBelow(m)} ${measuredAgainst(c)}`;
        return `Can't tell: ${c.metric} ran ${where} after the change, and the range, ${m.range}, includes zero.`;
      });
    case "near-zero-noise":
      return withEstimate(
        c,
        (m) => `Nothing moved beyond normal swings: ${c.metric} stayed within ${m.within} of ${measuredAgainst(c)} after the change.`
      );
    case "near-zero-precise":
      return withEstimate(c, (m) => {
        const stayed = `${c.metric} stayed within ${m.within} of ${measuredAgainst(c)} after the change`;
        return `No sign it worked: ${stayed}, and that rules out the ${thresholdText(c)} that would matter.`;
      });
    case "near-zero-unreliable-baseline":
      return withEstimate(c, (m) => {
        const stayed = `${c.metric} stayed within ${m.within} of ${measuredAgainst(c)} after the change`;
        return `Can't tell: ${stayed}, and ${weakClause(c)} keeps that from settling it.`;
      });
    case "opposite-direction":
      return withEstimate(c, () => `${clause(c)}, the opposite of what you wanted.`);
    case "opposite-direction-weak":
      return withEstimate(c, (m) => {
        const ran = `${c.Metric} ran ${m.size} ${aboveBelow(m)} ${measuredAgainst(c)} after the change`;
        return `${ran}, the opposite of what you wanted, and ${weakClause(c)} keeps the cause from being told.`;
      });
    case "below-threshold-precise":
      return withEstimate(
        c,
        (m) => `${clause(c)}, and the whole range, ${m.range}, falls under the ${thresholdText(c)} that would matter.`
      );
    case "weak-identification":
      return withEstimate(c, () => `${clause(c)}, and ${weakClause(c)} keeps the cause from being told.`);
    case "no-threshold":
      return withEstimate(c, () => `${clause(c)}; you did not say how much would matter.`);
    case "threshold-not-applicable":
      return withEstimate(
        c,
        () => `${clause(c)}; the pre-period average is too close to zero for a percent threshold to apply.`
      );
    case "threshold-not-settled":
      return withEstimate(
        c,
        (m) => `${clause(c)}, and the range, ${m.range}, does not settle whether it cleared the ${thresholdText(c)} bar.`
      );
    case "below-target":
      return withEstimate(c, () => `${clause(c)}, short of ${bar(c)}.`);
    case "target-not-settled":
      return withEstimate(
        c,
        (m) => `${clause(c)}, and the range, ${m.range}, does not settle whether it reached ${bar(c)}.`
      );
    case "robustness":
      return withEstimate(c, () => {
        const failing = failingCheck(c);
        if (failing === null) return `${clause(c)}, clearing ${bar(c)}, and one check did not hold.`;
        return `${clause(c)}, clearing ${bar(c)}, and ${failing.connector}: ${failing.sentence}`;
      });
    case "supported":
      return withEstimate(c, () => `${clause(c)}, clearing ${bar(c)}.`);
  }
}
function details(input) {
  const c = context2(input);
  const { result: r } = c;
  const out = [];
  const push = (topic, text) => {
    if (text !== null && text.length > 0) out.push({ topic, text });
  };
  push("change", changeSentence(c));
  push("method", methodSentence(c));
  push("fallback", r.fallback);
  push("effect", effectSentence(c));
  push("seasonality", seasonalitySentence(c));
  push("trend", trendSentence(c));
  push("placebo", placeboSentence(c));
  push("windows", r.robustness?.windows.sentence ?? null);
  push("outliers", r.robustness?.outliers.sentence ?? null);
  push("alternative", r.alternative.sentence);
  for (const step2 of r.dimensions.identificationSteps) push("identification", step2.sentence);
  push("materiality", materialitySentence(c));
  push("sufficiency", sufficiencySentence(c));
  push("effect", nearZeroSentence(c));
  for (const normalization of r.series.normalizations) push("normalization", normalization.message);
  for (const gap of r.series.gaps) push("normalization", gapSentence(gap, c.frequency));
  push("next", r.next.sentence);
  return out;
}
function context2(input) {
  const { result } = input;
  const style = { unit: result.series.unit, currencySymbol: result.series.currencySymbol };
  return {
    input,
    result,
    frequency: result.series.frequency,
    style,
    metric: name(result.series, result.question),
    Metric: Name(result.series, result.question),
    measured: result.estimate === null ? null : measure(result.estimate, style)
  };
}
function measure(estimate, style) {
  const { interval, effect, effectPercent, intervalPercent } = estimate;
  const absoluteHalfWidth = halfWidth(interval);
  const sign2 = effect < 0 ? "down" : "up";
  const absolute = formatAbsolute(Math.abs(effect), absoluteHalfWidth, style);
  if (effectPercent !== null && intervalPercent !== null) {
    const point = toPoints(effectPercent);
    const hw = toPoints(halfWidth(intervalPercent));
    const lower = toPoints(intervalPercent.lower);
    const upper = toPoints(intervalPercent.upper);
    return {
      size: formatPercent(Math.abs(point), hw),
      range: formatPercentRange(lower, upper, point, hw),
      within: formatPercent(Math.max(Math.abs(lower), Math.abs(upper)), hw),
      absolute,
      percent: true,
      percentHalfWidth: hw,
      absoluteHalfWidth,
      sign: sign2
    };
  }
  const widest = Math.max(Math.abs(interval.lower), Math.abs(interval.upper));
  return {
    size: absolute,
    range: formatAbsoluteRange(interval.lower, interval.upper, absoluteHalfWidth, style),
    within: formatAbsolute(widest, absoluteHalfWidth, style),
    absolute,
    percent: false,
    percentHalfWidth: null,
    absoluteHalfWidth,
    sign: sign2
  };
}
function withEstimate(c, build) {
  if (c.measured === null || c.result.estimate === null) return NO_ESTIMATE;
  return build(c.measured, c.result.estimate);
}
function clause(c) {
  if (c.measured === null) return NO_ESTIMATE;
  return causalClause(c.result.dimensions.identification, c.measured.sign, c.metric, c.measured.size, measuredAgainst(c));
}
function measuredAgainst(c) {
  return baseline(c.result.estimate?.method ?? "its", c.metric);
}
function aboveBelow(m) {
  return m.sign === "up" ? "above" : "below";
}
function tooEarly(c) {
  const n = c.result.series.postPresentAll;
  const lag = c.result.question.lagPeriods;
  const f = c.frequency;
  const had = lag > 0 ? `${formatCount(n)} ${unit(f, n)} after the ${formatCount(lag)}-${unit(f)} lag had values` : `${formatCount(n)} ${unit(f, n)} since the change had values`;
  return `Too early to tell: ${had}, and ${formatCount(MIN_POST)} are needed.`;
}
function beforeAfterOnly(c) {
  const raw = rawMove(c);
  if (raw === null) return NO_ESTIMATE;
  const nPre = c.result.series.prePresent;
  const history = `${formatCount(nPre)} ${unit(c.frequency, nPre)} of history is too few to measure against`;
  return `Can't tell: ${c.metric} ${raw.verb} ${raw.size} after the change, and ${history}.`;
}
function alternativeExplains(c) {
  const raw = rawMove(c);
  if (raw === null) return NO_ESTIMATE;
  const a = c.result.alternative;
  const kind = a.explainedBy ?? a.strongest?.kind ?? null;
  const candidate = kind === null ? null : a.candidates.find((x) => x.kind === kind) ?? a.strongest;
  const opening = `${c.Metric} ${raw.verb} ${raw.size} after the change, and`;
  if (kind === "seasonal" && candidate !== null && !seasonallyAdjusted(c)) {
    const earlier = `the same stretch of the calendar one ${cycleWord(c.frequency)} earlier`;
    return `${opening} ${earlier} matches ${formatShare(candidate.strength)} of it.`;
  }
  return `${opening} ${alternativeClause(c, kind, raw.fell)} explains it as well.`;
}
function alternativeClause(c, kind, fell) {
  switch (kind) {
    case "trend":
      return "the trend it was already on";
    case "seasonal":
      return `the same stretch of the calendar one ${cycleWord(c.frequency)} earlier`;
    case "outliers":
      return outlierClause(c);
    case "return":
      return fell ? "a return to normal after a spike just before it" : "a return to normal after a dip just before it";
    case "control":
      return "the comparison group moving the same way";
    case null:
      return "an explanation the data can test";
  }
}
function outlierClause(c) {
  const f = c.frequency;
  const r = c.result.robustness;
  const e = c.result.estimate;
  if (r === null || e === null) return `one unusual ${unit(f)}`;
  const sign2 = e.effect < 0 ? -1 : 1;
  const twoShrinksMore = sign2 * r.outliers.effectWithoutTwo < sign2 * r.outliers.effectWithoutOne;
  if (twoShrinksMore) return `two unusual ${unit(f, 2)}`;
  return `one unusual ${unit(f)} (${dates(periodAt2(c, r.outliers.dropped[0]), f)})`;
}
function periodAt2(c, index) {
  return c.input.periods[index] ?? { index, date: null, value: null };
}
function seasonallyAdjusted(c) {
  const fit2 = c.result.treatedIts ?? c.result.estimate;
  return fit2?.seasonality === "adjusted";
}
function rawMove(c) {
  const d = c.result.descriptive;
  if (d === null) return null;
  const hw = descriptiveHalfWidth(c, d);
  const fell = d.absoluteChange < 0;
  const verb = fell ? "fell" : "rose";
  if (d.percentChange !== null && d.preMean > 0) {
    const points = toPoints(d.percentChange);
    return { verb, size: formatPercent(Math.abs(points), toPoints(hw / d.preMean)), fell };
  }
  return { verb, size: formatAbsolute(Math.abs(d.absoluteChange), hw, c.style), fell };
}
function descriptiveHalfWidth(c, d) {
  const given = c.input.descriptiveHalfWidth;
  if (given !== null && Number.isFinite(given) && given > 0) return given;
  return c.measured?.absoluteHalfWidth ?? Math.abs(d.absoluteChange);
}
function weakClauseFor(reason, f) {
  switch (reason) {
    case "short-history":
      return `fewer than ${formatCount(GOOD_PRE)} ${unit(f, GOOD_PRE)} of history`;
    case "pre-trend-unstable":
      return "an unstable trend before the change";
    case "windows-sensitive":
      return "a result that changes with the window";
    case "outliers-sensitive":
      return `a result that rests on one ${unit(f)}`;
    case "seasonality-not-ruled-out":
      return "an unchecked seasonal pattern";
    case "noise-model-at-limit":
      return "a series that drifts like a random walk";
    case "placebo-in-bulk":
      return "a change this size being common at other dates";
    default:
      return null;
  }
}
function weakClause(c) {
  const { dimensions: dimensions2, robustness: robustness2 } = c.result;
  const f = c.frequency;
  for (const step2 of dimensions2.identificationSteps) {
    if (step2.to !== "weak") continue;
    const text2 = weakClauseFor(step2.reason, f);
    if (text2 !== null) return text2;
  }
  let reason = null;
  if (!dimensions2.preTrendStable) reason = "pre-trend-unstable";
  else if (robustness2?.windows.status === "sensitive") reason = "windows-sensitive";
  else if (robustness2?.outliers.status === "sensitive") reason = "outliers-sensitive";
  const text = reason === null ? null : weakClauseFor(reason, f);
  return text ?? "a baseline the checks did not confirm";
}
function givenPercent(fraction, c) {
  const points = toPoints(fraction);
  const hw = c.measured?.percentHalfWidth ?? Math.abs(points);
  return formatPercent(points, Math.min(hw, Math.abs(points)));
}
function thresholdText(c) {
  const q = c.result.question;
  switch (q.thresholdSource) {
    case "minimumMeaningful":
      return q.minimumMeaningful === null ? THRESHOLD_WORD : givenPercent(q.minimumMeaningful, c);
    case "target":
      return q.target === null ? THRESHOLD_WORD : givenPercent(q.target, c);
    case "minimumMeaningfulAbsolute": {
      if (q.minimumMeaningfulAbsolute === null) return THRESHOLD_WORD;
      const hw = c.measured?.absoluteHalfWidth ?? Math.abs(q.minimumMeaningfulAbsolute);
      return formatAbsolute(q.minimumMeaningfulAbsolute, hw, c.style);
    }
    case "none":
      return THRESHOLD_WORD;
  }
}
function bar(c) {
  const q = c.result.question;
  if (q.target !== null && c.result.dimensions.targetState !== "none") {
    return `the ${givenPercent(q.target, c)} you expected`;
  }
  return `the ${thresholdText(c)} bar`;
}
function failingCheck(c) {
  const r = c.result.robustness;
  if (r === null) return null;
  const check = [r.placebo, r.windows, r.outliers].find((k) => k.status !== "robust");
  if (check === void 0) return null;
  const connector = check.status === "not-assessed" ? "one check could not run" : "one check did not hold";
  return { connector, sentence: lowerFirst(firstSentence(check.sentence)) };
}
function firstSentence(text) {
  const end = text.indexOf(". ");
  return end < 0 ? text : text.slice(0, end + 1);
}
function lowerFirst(text) {
  return text.charAt(0).toLowerCase() + text.slice(1);
}
function changeSentence(c) {
  const d = c.result.descriptive;
  if (d === null) return null;
  const f = c.frequency;
  const hw = descriptiveHalfWidth(c, d);
  const W = c.result.question.window.length;
  let change = formatAbsolute(d.absoluteChange, hw, c.style);
  if (d.percentChange !== null && d.preMean > 0) {
    change += ` (${formatPercent(toPoints(d.percentChange), toPoints(hw / d.preMean))})`;
  }
  const before = `Before the change ${c.metric} averaged ${formatLevel(d.preMean, hw, c.style)} over ${formatCount(d.prePeriods)} ${unit(f, d.prePeriods)}`;
  const after = `over the ${formatCount(W)} ${unit(f, W)} after, ${agree(c.metric, "it", "they")} averaged ${formatLevel(d.postMean, hw, c.style)}`;
  return `${before}; ${after}, a change of ${change}.`;
}
function methodSentence(c) {
  const f = c.frequency;
  const W = c.result.question.window.length;
  const window = `${formatCount(W)} ${unit(f, W)}`;
  const intervalMethod = c.result.estimate?.intervalMethod ?? null;
  const tail = intervalMethod === null ? "" : ` ${intervalMethod}`;
  switch (c.result.method) {
    case "none":
      return null;
    case "before-after":
      return "Method: before and after means only.";
    case "its":
      return `Method: a line fitted to the ${unit(f)}s before the change and projected forward, with the gap read over the ${window} after.${tail}`;
    case "did":
      return `Method: the treated series minus the comparison group over the ${window} after the change.${tail}`;
  }
}
function effectSentence(c) {
  const m = c.measured;
  if (m === null) return null;
  const size = m.percent ? ` (${m.size})` : "";
  return `Against ${measuredAgainst(c)}, ${c.metric} ran ${m.absolute}${size} ${aboveBelow(m)} expected over those ${unit(c.frequency)}s; the range is ${m.range}.`;
}
function seasonalPeriod(c, e) {
  if (e.seasonalPeriod !== null) return e.seasonalPeriod;
  const f = c.frequency;
  return f === "weekly" || f === "monthly" ? SEASON_PERIOD[f] : null;
}
function seasonalitySentence(c) {
  const e = c.result.estimate;
  if (e === null || e.seasonality === "not-applicable") return null;
  const f = c.frequency;
  const S = seasonalPeriod(c, e);
  if (S === null) return null;
  if (e.seasonality === "adjusted") {
    return `Seasonality was adjusted with ${formatCount(e.harmonics)} harmonics of a ${formatCount(S)}-${unit(f)} cycle estimated from the whole series.`;
  }
  const nPre = c.result.series.prePresent;
  const nPost = c.result.series.postPresent;
  if (nPre < S) {
    return `Seasonality could not be ruled out: ${formatCount(nPre)} ${unit(f, nPre)} before the change, ${formatCount(S)} needed to see every phase before it.`;
  }
  const rows = nPre + nPost;
  return `Seasonality could not be ruled out: ${formatCount(rows)} ${unit(f, rows)} went into the fit, and ${formatCount(2 * S)} are needed.`;
}
function slopeHalfWidth(e, slope, slopeT) {
  const t = halfWidth(e.interval) / e.standardError;
  const hw = t * Math.abs(slope / slopeT);
  return Number.isFinite(hw) && hw > 0 ? hw : Math.abs(slope);
}
function trendSentence(c) {
  const e = c.result.estimate;
  if (e === null || e.preSlope === null || e.preSlopeT === null) return null;
  const flat = Math.abs(e.preSlopeT) < T_SLOPE;
  const was = agree(c.metric, "was", "were");
  const opening = flat ? `Before the change ${c.metric} ${was} flat.` : `Before the change ${c.metric} ${was} ${e.preSlope < 0 ? "falling" : "rising"} about ${formatAbsolute(Math.abs(e.preSlope), slopeHalfWidth(e, e.preSlope, e.preSlopeT), c.style)} per ${unit(c.frequency)}.`;
  return e.preTrend.stable ? opening : `${opening} ${UNSTABLE_SENTENCE}`;
}
function placeboSentence(c) {
  const p = c.result.placebo;
  const r = c.result.robustness;
  if (p === null || r === null) return null;
  const f = c.frequency;
  const window = `The window compared was the first ${formatCount(p.window)} ${unit(f, p.window)} with values after the change against ${formatCount(p.positions)} same-length stretches before it.`;
  return `${r.placebo.sentence} ${window}`;
}
function materialitySentence(c) {
  const d = c.result.dimensions;
  const q = c.result.question;
  let text = null;
  switch (d.thresholdState) {
    case "meets":
      text = `The smallest effect that would matter is ${thresholdText(c)}; the whole range clears it.`;
      break;
    case "clearly-below":
      text = `The smallest effect that would matter is ${thresholdText(c)}; the whole range falls under it.`;
      break;
    case "possibly-below":
      text = `The smallest effect that would matter is ${thresholdText(c)}; the range includes it.`;
      break;
    case "not-assessed":
      if (d.materialityReason === "no-threshold") text = "You did not say how much would matter.";
      if (d.materialityReason === "pre-level-near-zero") {
        text = "The pre-period average is too close to zero for a percent threshold to apply.";
      }
      break;
  }
  if (q.target !== null && d.targetState !== "none") {
    const read = d.targetState === "met" ? "clears it" : d.targetState === "missed" ? "falls under it" : "includes it";
    const target = `You expected ${givenPercent(q.target, c)}; the range ${read}.`;
    text = text === null ? target : `${text} ${target}`;
  }
  return text;
}
function sufficiencySentence(c) {
  const f = c.frequency;
  const nPre = c.result.series.prePresent;
  const nPost = c.result.series.postPresent;
  const counts = `${formatCount(nPre)} ${unit(f, nPre)} came before the change and ${formatCount(nPost)} after.`;
  switch (c.result.dimensions.sufficiency) {
    case "high":
      return `${counts} That is enough for a clear reading.`;
    case "medium":
      return `${counts} Twelve on each side would be firmer.`;
    case "low":
      return `${counts} That is near the minimum.`;
    case "too-early":
      return counts;
  }
}
function nearZeroSentence(c) {
  if (c.result.dimensions.effectBasis !== "noise" || c.result.estimate === null) return null;
  return `Near zero here means within one typical ${unit(c.frequency)}'s swing of ${measuredAgainst(c)}; no threshold was given.`;
}
function gapSentence(gap, f) {
  const start = { index: (gap.afterIndex ?? -1) + 1, date: gap.start, value: null };
  const treatment = gap.treatment === "dropped" ? "dropped" : "skipped by every fit";
  return `${formatCount(gap.length)} ${unit(f, gap.length)} from ${dates(start, f)} were missing and were ${treatment}.`;
}

// src/engine/nextMeasurement.ts
var PLACEBO_HISTORY = PLACEBO_MIN_N * PLACEBO_W_MIN;
function criticalT4(df) {
  return tQuantile(1 - (1 - CONFIDENCE) / 2, df);
}
function consecutive(from, count) {
  return Array.from({ length: Math.max(0, count) }, (_, i) => from + i);
}
function headlineDesign(headline2) {
  const { fit: fit2 } = headline2;
  const times = fit2.design.times;
  return {
    method: headline2.method,
    preTimes: times.slice(0, fit2.preRows),
    postTimes: times.slice(fit2.preRows),
    Tb: fit2.Tb,
    season: headline2.method === "its" ? headline2.fit.season : null,
    phi: fit2.phi,
    sigma2: fit2.sigma2
  };
}
function itsContrast(k, postTimes, Tb) {
  const c = new Array(k).fill(0);
  c[2] = 1;
  c[3] = mean(postTimes.map((t) => t - Tb));
  return c;
}
function designHalfWidth(design, preTimes, postTimes) {
  if (postTimes.length === 0) {
    return Infinity;
  }
  const times = [...preTimes, ...postTimes];
  const rows = design.method === "its" ? itsDesign(times, design.Tb, design.season) : didDesign(times, design.Tb);
  const k = rows[0]?.length ?? 0;
  const df = times.length - k;
  if (df <= 0) {
    return Infinity;
  }
  let fit2;
  try {
    fit2 = ols(rows, new Array(times.length).fill(0));
  } catch (error2) {
    if (error2 instanceof SingularDesignError) {
      return Infinity;
    }
    throw error2;
  }
  const timed = { rows, times };
  const contrast = design.method === "its" ? itsContrast(k, postTimes, design.Tb) : [...DID_CONTRAST];
  const weights = effectWeights(fit2, timed, contrast);
  const se = differenceSe(/* @__PURE__ */ new Map(), weights, design.phi, design.sigma2);
  return criticalT4(effectiveDf(df, design.phi)) * se;
}
function hwPost(design, W) {
  return designHalfWidth(design, design.preTimes, consecutive(design.Tb, W));
}
function hwPre(design, e) {
  return designHalfWidth(design, [...consecutive(-e, e), ...design.preTimes], design.postTimes);
}
function windowCap(T0) {
  return Math.min(Math.max(T0, MIN_POST), MAX_WINDOW);
}
function searchPost(design, W, T0, bar2) {
  const cap = windowCap(T0);
  for (let next = W + 1; next <= cap; next++) {
    if (hwPost(design, next) <= bar2) {
      return next - W;
    }
  }
  return null;
}
function searchPre(design, bar2) {
  for (let e = 1; e <= MAX_WINDOW; e++) {
    if (hwPre(design, e) <= bar2) {
      return e;
    }
  }
  return null;
}
function recommendation(kind, sentence, periods = null, index = null) {
  return { kind, sentence, periods, index };
}
function wait(periods, frequency) {
  return recommendation("wait", `Check again in ${periods} more ${unit(frequency, periods)}.`, periods);
}
function moreHistory(periods, frequency) {
  return recommendation(
    "more-history",
    `Paste ${periods} more ${unit(frequency, periods)} from before the change, if they exist.`,
    periods
  );
}
function morePostPeriods(periods, frequency, sentence) {
  const words = unit(frequency, periods);
  const text = sentence === "narrow" ? `About ${periods} more ${words} after the change would narrow the range enough to settle it, if the estimate holds.` : `Another ${periods} ${words} after the change would show whether the result holds past the current window.`;
  return recommendation("more-post-periods", text, periods);
}
function comparisonGroup() {
  return recommendation("comparison-group", "A comparison group that did not get the change would settle it.");
}
function differentComparisonGroup() {
  return recommendation(
    "different-comparison-group",
    "A comparison group whose trend matched this one before the change would settle it."
  );
}
function stateThreshold(form) {
  const text = form === "effect" ? "State the smallest effect that would matter; the range is already tight enough to judge against it." : "State the smallest change that would matter in the series' own units; a percent of an average this close to zero cannot be read.";
  return recommendation("state-threshold", text);
}
function checkUnusualPeriods(periods, index, frequency) {
  return recommendation(
    "check-unusual-periods",
    `Check what happened on ${dates(periods, frequency)}; the result rests on those ${unit(frequency, periods.length)}.`,
    null,
    index
  );
}
function oneMoreCycle(periods, frequency) {
  return recommendation(
    "one-more-cycle",
    `One more full ${cycleWord(frequency)} of history (${periods} ${unit(frequency, periods)}) would let seasonality be checked.`,
    periods
  );
}
function keepMeasuring(periods, frequency) {
  return recommendation(
    "keep-measuring",
    `Keep measuring; recheck after ${periods} more ${unit(frequency, periods)}.`,
    periods
  );
}
function atLeastModerate(identification) {
  return identification === "moderate" || identification === "strong";
}
function cyclePeriods(frame) {
  const decision = seasonalTerms(frame.frequency, frame.nPre, frame.nPost);
  if (decision.season !== null || decision.period === null) {
    return null;
  }
  const S = decision.period;
  return Math.max(1, 2 * S - (frame.nPre + frame.nPost), S - frame.nPre);
}
function oneMoreCycleOrComparison(frame) {
  const periods = cyclePeriods(frame);
  return periods === null ? comparisonGroup() : oneMoreCycle(periods, frame.frequency);
}
function droppedPeriods(periods, dropped) {
  return dropped.map((index) => periods[index] ?? { index, date: null, value: null });
}
function byAlternative(input, frame) {
  switch (input.alternative.explainedBy) {
    case "trend":
      return comparisonGroup();
    case "seasonal":
      return oneMoreCycleOrComparison(frame);
    case "outliers": {
      if (input.robustness === null) {
        return null;
      }
      const dropped = input.robustness.outliers.dropped;
      return checkUnusualPeriods(droppedPeriods(input.periods, dropped), dropped[0], frame.frequency);
    }
    case "return":
      return moreHistory(Math.max(MIN_PRE, frame.nPre), frame.frequency);
    case "control":
      return differentComparisonGroup();
    case null:
      return null;
  }
}
function forWeakReason(reason, frame) {
  switch (reason) {
    case "short-history":
      return moreHistory(Math.max(1, GOOD_PRE - frame.nPre), frame.frequency);
    case "pre-trend-unstable":
    case "noise-model-at-limit":
    case "placebo-in-bulk":
      return comparisonGroup();
    case "windows-sensitive":
    case "outliers-sensitive":
      return morePostPeriods(frame.W, frame.frequency, "hold");
    case "seasonality-not-ruled-out":
      return oneMoreCycleOrComparison(frame);
    default:
      return null;
  }
}
function byWeakStep(steps, frame) {
  for (const step2 of steps) {
    if (step2.to !== "weak" || step2.from === "weak") {
      continue;
    }
    const found = forWeakReason(step2.reason, frame);
    if (found !== null) {
      return found;
    }
  }
  return null;
}
function searchBoth(design, frame, bar2) {
  if (design === null) {
    return null;
  }
  const post = searchPost(design, frame.W, frame.T0, bar2);
  if (post !== null) {
    return morePostPeriods(post, frame.frequency, "narrow");
  }
  const pre = searchPre(design, bar2);
  if (pre !== null) {
    return moreHistory(pre, frame.frequency);
  }
  return null;
}
function nextMeasurement(input) {
  const { verdict: verdict2, dimensions: dimensions2, robustness: robustness2, estimate } = input;
  const frame = {
    frequency: input.series.frequency,
    nPre: input.series.prePresent,
    nPost: input.series.postPresent,
    nPostAll: input.series.postPresentAll,
    T0: input.question.changeIndex,
    W: input.question.window.length,
    hasControl: input.series.hasControl
  };
  const { frequency, W } = frame;
  const reason = verdict2.reason;
  const design = input.headline === null ? null : headlineDesign(input.headline);
  if (reason === "too-early") {
    return wait(Math.max(1, MIN_POST - frame.nPostAll), frequency);
  }
  if (reason === "no-estimate" || reason === "before-after-only") {
    return moreHistory(Math.max(1, MIN_PRE - frame.nPre), frequency);
  }
  if (reason === "alternative-explains") {
    const found = byAlternative(input, frame);
    if (found !== null) {
      return found;
    }
  }
  if (reason === "interval-includes-zero" && estimate !== null) {
    const size = Math.abs(estimate.effect);
    const floor = estimate.noiseSd * SMALL_MOVE_SHARE;
    if (size < floor && input.thresholdAbs === null) {
      return stateThreshold("effect");
    }
    const found = searchBoth(design, frame, Math.max(size, floor));
    if (found !== null) {
      return found;
    }
    return frame.hasControl ? keepMeasuring(W, frequency) : comparisonGroup();
  }
  if (reason === "near-zero-unreliable-baseline" || reason === "weak-identification" || reason === "opposite-direction-weak") {
    const found = byWeakStep(dimensions2.identificationSteps, frame);
    if (found !== null) {
      return found;
    }
  }
  if (robustness2 !== null && robustness2.placebo.status === "not-assessed" && atLeastModerate(dimensions2.identification)) {
    return moreHistory(Math.max(1, PLACEBO_HISTORY - frame.T0), frequency);
  }
  if (reason === "no-threshold") {
    return stateThreshold("effect");
  }
  if (reason === "threshold-not-applicable") {
    return stateThreshold("series-units");
  }
  if (reason === "threshold-not-settled" || reason === "target-not-settled") {
    const bound = reason === "threshold-not-settled" ? input.thresholdAbs : input.targetAbs;
    if (estimate !== null && bound !== null) {
      const found = searchBoth(design, frame, Math.abs(estimate.effect - bound));
      if (found !== null) {
        return found;
      }
    }
    return keepMeasuring(W, frequency);
  }
  if (robustness2 !== null && robustness2.placebo.status === "sensitive" && atLeastModerate(dimensions2.identification)) {
    return comparisonGroup();
  }
  return keepMeasuring(W, frequency);
}

// src/engine/placebo.ts
var VARIANCE_FLOOR = 1e-12;
function at6(xs, i) {
  return xs[i];
}
function at22(rows, i) {
  return rows[i];
}
function presentTimes(values, from, to) {
  const times = [];
  const last = Math.min(to, values.length - 1);
  for (let t = Math.max(0, from); t <= last; t++) {
    const v = values[t];
    if (v !== null && v !== void 0) {
      times.push(t);
    }
  }
  return times;
}
function quadraticForm2(M, a) {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    const row = M[i];
    for (let j = 0; j < a.length; j++) {
      s += at6(a, i) * at6(row, j) * at6(a, j);
    }
  }
  return s;
}
function columnMeans(rows) {
  const k = rows[0].length;
  const out = new Array(k).fill(0);
  for (const row of rows) {
    for (let j = 0; j < k; j++) {
      out[j] = at6(out, j) + at6(row, j) / rows.length;
    }
  }
  return out;
}
function placeboWindow(T0, W) {
  const upper = Math.min(PLACEBO_W_CAP, W);
  return Math.max(PLACEBO_W_MIN, Math.min(upper, Math.floor(T0 / PLACEBO_DIVISOR)));
}
function placeboTiles(values, T0, Wp) {
  const needed = Math.ceil(PLACEBO_TILE_MIN_SHARE * Wp);
  const tiles = [];
  for (let j = 1; j * Wp <= T0; j++) {
    const index = T0 - j * Wp;
    const times = presentTimes(values, index, index + Wp - 1);
    if (times.length < needed) {
      continue;
    }
    tiles.push({ index, times });
  }
  return tiles;
}
function realTile(values, Tb, W, Wp) {
  return presentTimes(values, Tb, Tb + W - 1).slice(0, Wp);
}
function itsModel(frame) {
  const pre = fitPre(frame.values, frame.T0, frame.Tb, frame.season);
  if (pre === null) {
    return null;
  }
  return {
    row: (t) => at22(preDesign([t], frame.Tb, frame.season), 0),
    xtxInverse: pre.ols.xtxInverse,
    residuals: pre.residuals
  };
}
function didModel(frame) {
  const times = presentTimes(frame.values, 0, frame.T0 - 1);
  if (times.length < 2) {
    return null;
  }
  const y = times.map((t) => frame.values[t]);
  const fit2 = ols(times.map(() => [1]), y);
  const level = at6(fit2.beta, 0);
  const residuals = /* @__PURE__ */ new Map();
  frame.values.forEach((v, t) => {
    if (v !== null) {
      residuals.set(t, v - level);
    }
  });
  return { row: () => [1], xtxInverse: fit2.xtxInverse, residuals };
}
function preModel(frame) {
  if (frame.T0 < 1) {
    return null;
  }
  return frame.method === "did" ? didModel(frame) : itsModel(frame);
}
function tileStatistic(model, times, sign2, sigma) {
  const rows = times.map(model.row);
  const xBar = columnMeans(rows);
  const v = 1 / times.length + sign2 * quadraticForm2(model.xtxInverse, xBar);
  const gap = mean(times.map((t) => model.residuals.get(t)));
  if (v <= VARIANCE_FLOOR) {
    return { gap: 0, statistic: 0 };
  }
  return { gap, statistic: gap / (sigma * Math.sqrt(v)) };
}
function placeboDistribution(frame) {
  if (!Number.isFinite(frame.noiseSd) || frame.noiseSd <= 0) {
    return null;
  }
  const model = preModel(frame);
  if (model === null) {
    return null;
  }
  const window = placeboWindow(frame.T0, frame.W);
  const real = realTile(frame.values, frame.Tb, frame.W, window);
  if (real.length === 0) {
    return null;
  }
  const distribution = placeboTiles(frame.values, frame.T0, window).map((tile) => {
    const { gap, statistic } = tileStatistic(model, tile.times, -1, frame.noiseSd);
    return { index: tile.index, statistic, gap };
  });
  const { gap: realGap, statistic: realStatistic } = tileStatistic(model, real, 1, frame.noiseSd);
  return { window, distribution, realStatistic, realGap };
}
function countAtLeastAsLarge(statistics, real, direction) {
  const g = direction === "up" ? 1 : -1;
  let count = 0;
  for (const z of statistics) {
    if (g * z >= g * real) {
      count++;
    }
  }
  return count;
}
function countedDirection(direction, effect) {
  if (direction === "up" && effect === "negative") {
    return "down";
  }
  if (direction === "down" && effect === "positive") {
    return "up";
  }
  return direction;
}
function placeboCountSentence(k, N) {
  return `A change this size showed up at ${k} of ${N} other dates.`;
}
function placeboNotAssessedSentence(N) {
  return `Only ${N} other dates were available for comparison, too few to rate.`;
}
function placeboSentence2(placebo2) {
  return placebo2.assessed ? placeboCountSentence(placebo2.atLeastAsLarge, placebo2.positions) : placeboNotAssessedSentence(placebo2.positions);
}
function constructionSentence(Wp, frequency) {
  const one = unit(frequency);
  return `Each placebo date pretends the change happened ${Wp} ${unit(frequency, Wp)} before the previous one, uses only ${one}s before the real change, measures the same ${Wp}-${one} gap from the same pre-trend line, and is scaled to the same noise level as the real date.`;
}
function placebo(input) {
  const result = placeboDistribution(input);
  if (result === null) {
    return null;
  }
  const statistics = result.distribution.map((position) => position.statistic);
  const stated = countAtLeastAsLarge(statistics, result.realStatistic, input.direction);
  const reading = effectReading(input.interval.lower, input.interval.upper, input.mAbs, input.noiseSd);
  const counted = countedDirection(input.direction, reading.effect);
  const atLeastAsLarge = counted === input.direction ? stated : countAtLeastAsLarge(statistics, result.realStatistic, counted);
  const positions = result.distribution.length;
  return {
    window: result.window,
    positions,
    atLeastAsLarge,
    atLeastAsLargeStated: stated,
    countedDirection: counted,
    realStatistic: result.realStatistic,
    realGap: result.realGap,
    distribution: result.distribution,
    assessed: positions >= PLACEBO_MIN_N,
    construction: constructionSentence(result.window, input.frequency)
  };
}

// src/engine/robustness.ts
var SHORTER_FLOOR = 3;
var SECOND_SHORTER_FROM = 8;
var THREE_QUARTERS = 0.75;
var REFIT_MIN_ROWS = 2;
var NO_DROP3 = /* @__PURE__ */ new Set();
function presentCount(values, from, to) {
  let count = 0;
  const last = Math.min(to, values.length - 1);
  for (let t = Math.max(0, from); t <= last; t++) {
    const v = values[t];
    if (v !== null && v !== void 0) {
      count++;
    }
  }
  return count;
}
function refit(headline2, values, W, drop) {
  const { T0, Tb } = headline2.fit;
  const L = Tb - T0;
  return headline2.method === "its" ? fitIts(values, T0, L, W, headline2.fit.season, drop) : fitDid(values, T0, L, W, drop);
}
function standardized(difference, se) {
  return se > 0 ? difference / se : 0;
}
function periodAt3(periods, index) {
  return periods[index] ?? { index, date: null, value: null };
}
function join(parts) {
  if (parts.length <= 1) {
    return parts[0] ?? "";
  }
  if (parts.length === 2) {
    return `${parts[0]} and ${parts[1]}`;
  }
  return `${parts.slice(0, -1).join(", ")}, and ${parts[parts.length - 1]}`;
}
function alternativeWindows(W, nPostIdx) {
  const windows = [
    { kind: "shorter", length: Math.max(SHORTER_FLOOR, Math.floor(W / 2)) }
  ];
  if (W >= SECOND_SHORTER_FROM) {
    windows.push({ kind: "shorter", length: Math.floor(THREE_QUARTERS * W) });
  }
  if (nPostIdx > W) {
    windows.push({ kind: "longer", length: nPostIdx });
  }
  return windows;
}
function intervalExcludesZero(interval, mAbs, noiseSd) {
  const { effect } = effectReading(interval.lower, interval.upper, mAbs, noiseSd);
  return effect === "positive" || effect === "negative";
}
function windowAgrees(headlineEffect, excludesZero, refitEffect, se) {
  if (Math.abs(refitEffect - headlineEffect) > ROBUST_Z * se) {
    return false;
  }
  return !excludesZero || Math.sign(refitEffect) === Math.sign(headlineEffect);
}
function holdsSentence(W, windows, frequency) {
  const shorter = windows.filter((w) => w.kind === "shorter").map((w) => w.length).sort((a, b) => a - b);
  const longer = windows.find((w) => w.kind === "longer");
  const parts = [];
  const first = shorter[0];
  if (first !== void 0) {
    parts.push(`the first ${first}`);
  }
  parts.push(longer === void 0 ? `the full ${W}` : `the ${W}`);
  if (longer !== void 0) {
    parts.push(`all ${longer.length}`);
  }
  const last = longer === void 0 ? W : longer.length;
  return `The result holds over ${join(parts)} ${unit(frequency, last)} after the change.`;
}
function dependsSentence(W, failing, headlineEffect, hw, frequency, style) {
  const alternative = formatAbsolute(failing.effect, hw, style);
  const headline2 = formatAbsolute(headlineEffect, hw, style);
  const tail = "the result depends on the window.";
  if (failing.kind === "shorter") {
    return `The first ${failing.length} ${unit(frequency, failing.length)} show ${alternative}, against ${headline2} over all ${W} ${unit(frequency, W)}; ${tail}`;
  }
  return `All ${failing.length} ${unit(frequency, failing.length)} show ${alternative}, against ${headline2} over the first ${W} ${unit(frequency, W)}; ${tail}`;
}
function windowSentence(W, windows, skipped, failing, headlineEffect, hw, frequency, style) {
  if (windows.length === 0) {
    return "No alternative window held enough values to refit.";
  }
  const main = failing === null ? holdsSentence(W, windows, frequency) : dependsSentence(W, failing, headlineEffect, hw, frequency, style);
  const tail = skipped.map((length) => ` The first ${length} ${unit(frequency, length)} had too few values to refit.`).join("");
  return main + tail;
}
function windowCheck(input) {
  const { headline: headline2, values, frequency, style, mAbs, noiseSd } = input;
  const { fit: fit2 } = headline2;
  const nPostIdx = values.length - fit2.Tb;
  const excludesZero = intervalExcludesZero(fit2.interval, mAbs, noiseSd);
  const windows = [];
  const skipped = [];
  let failing = null;
  for (const window of alternativeWindows(fit2.W, nPostIdx)) {
    const present2 = presentCount(values, fit2.Tb, fit2.Tb + window.length - 1);
    const alternative = present2 < REFIT_MIN_ROWS ? null : refit(headline2, values, window.length, NO_DROP3);
    if (alternative === null) {
      skipped.push(window.length);
      continue;
    }
    const se = differenceSe(fit2.weights, alternative.weights, fit2.phi, fit2.sigma2);
    const record2 = {
      kind: window.kind,
      length: window.length,
      effect: alternative.effect,
      interval: alternative.interval,
      zDifference: standardized(alternative.effect - fit2.effect, se)
    };
    windows.push(record2);
    if (failing === null && !windowAgrees(fit2.effect, excludesZero, alternative.effect, se)) {
      failing = record2;
    }
  }
  return {
    status: failing === null ? "robust" : "sensitive",
    sentence: windowSentence(
      fit2.W,
      windows,
      skipped,
      failing,
      fit2.effect,
      halfWidth(fit2.interval),
      frequency,
      style
    ),
    windows,
    skipped
  };
}
function rankByInfluence(influence) {
  return [...influence].sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta) || a.index - b.index);
}
function classify(interval, mAbs, noiseSd, g) {
  return {
    effect: effectReading(interval.lower, interval.upper, mAbs, noiseSd).effect,
    state: thresholdState(interval.lower, interval.upper, g, mAbs)
  };
}
function outlierTriggered(headline2, refit2, difference, se) {
  const differs = headline2.effect !== refit2.effect || headline2.state !== refit2.state;
  return differs && Math.abs(difference) > ROBUST_Z * se;
}
function topTwo(influence) {
  const ranked = rankByInfluence(influence);
  const first = ranked[0];
  const second = ranked[1];
  if (first === void 0 || second === void 0) {
    throw new RangeError("The outlier check needs a fit with at least two rows.");
  }
  return [first, second];
}
function outlierCheck(input) {
  const { headline: headline2, values, periods, frequency, style, mAbs, noiseSd, g } = input;
  const { fit: fit2 } = headline2;
  const [first, second] = topTwo(fit2.influence);
  const dropped = [first.index, second.index];
  const standardizedResiduals = [first.standardizedResidual, second.standardizedResidual];
  const one = refit(headline2, values, fit2.W, /* @__PURE__ */ new Set([first.index]));
  const two = refit(headline2, values, fit2.W, /* @__PURE__ */ new Set([first.index, second.index]));
  if (one === null || two === null) {
    return {
      status: "not-assessed",
      sentence: `Too few values remained to refit without the most influential ${unit(frequency, 2)}.`,
      dropped,
      effectWithoutOne: fit2.effect,
      effectWithoutTwo: fit2.effect,
      zDifferences: [0, 0],
      standardizedResiduals
    };
  }
  const base2 = classify(fit2.interval, mAbs, noiseSd, g);
  const seOne = differenceSe(fit2.weights, one.weights, fit2.phi, fit2.sigma2);
  const seTwo = differenceSe(fit2.weights, two.weights, fit2.phi, fit2.sigma2);
  const oneTriggers = outlierTriggered(base2, classify(one.interval, mAbs, noiseSd, g), one.effect - fit2.effect, seOne);
  const twoTriggers = outlierTriggered(base2, classify(two.interval, mAbs, noiseSd, g), two.effect - fit2.effect, seTwo);
  const hw = halfWidth(fit2.interval);
  const headlineText = formatAbsolute(fit2.effect, hw, style);
  const firstPeriod = periodAt3(periods, first.index);
  const secondPeriod = periodAt3(periods, second.index);
  let sentence;
  if (oneTriggers) {
    sentence = `Without ${dates(firstPeriod, frequency)}, the effect is ${formatAbsolute(one.effect, hw, style)} instead of ${headlineText}; the result rests on that ${unit(frequency)}.`;
  } else if (twoTriggers) {
    sentence = `Without ${dates([firstPeriod, secondPeriod], frequency)}, the effect is ${formatAbsolute(two.effect, hw, style)} instead of ${headlineText}; the result rests on those ${unit(frequency, 2)}.`;
  } else {
    sentence = `Dropping the one or two most influential ${unit(frequency, 2)} (${dates([firstPeriod, secondPeriod], frequency)}) leaves the answer unchanged.`;
  }
  return {
    status: oneTriggers || twoTriggers ? "sensitive" : "robust",
    sentence,
    dropped,
    effectWithoutOne: one.effect,
    effectWithoutTwo: two.effect,
    zDifferences: [standardized(one.effect - fit2.effect, seOne), standardized(two.effect - fit2.effect, seTwo)],
    standardizedResiduals
  };
}
function placeboCheck(placebo2) {
  if (placebo2 === null) {
    return { status: "not-assessed", sentence: placeboNotAssessedSentence(0), fraction: null };
  }
  if (!placebo2.assessed) {
    return { status: "not-assessed", sentence: placeboSentence2(placebo2), fraction: null };
  }
  const fraction = placebo2.atLeastAsLarge / placebo2.positions;
  const robust = fraction <= PLACEBO_TOP;
  return {
    status: robust ? "robust" : "sensitive",
    sentence: `${placeboSentence2(placebo2)} That is ${robust ? "rare" : "common"} in this series.`,
    fraction
  };
}
function robustness(input) {
  return {
    windows: windowCheck(input),
    outliers: outlierCheck(input),
    placebo: placeboCheck(input.placebo)
  };
}

// src/engine/verdict.ts
var WORD_BY_REASON = {
  "too-early": "too-early",
  "no-estimate": "inconclusive",
  "before-after-only": "inconclusive",
  "alternative-explains": "inconclusive",
  "interval-includes-zero": "inconclusive",
  "near-zero-precise": "not-supported",
  "near-zero-noise": "not-supported",
  "near-zero-unreliable-baseline": "inconclusive",
  "opposite-direction": "not-supported",
  "opposite-direction-weak": "inconclusive",
  "below-threshold-precise": "not-supported",
  "weak-identification": "inconclusive",
  "no-threshold": "partially-supported",
  "threshold-not-applicable": "partially-supported",
  "threshold-not-settled": "partially-supported",
  "below-target": "partially-supported",
  "target-not-settled": "partially-supported",
  robustness: "partially-supported",
  supported: "supported"
};
function decide(reason, path) {
  return { word: WORD_BY_REASON[reason], reason, path };
}
function atLeastModerate2(identification) {
  return identification === "moderate" || identification === "strong";
}
function baselineReliable(d, r, estimatePresent) {
  return estimatePresent && d.preTrendStable && r !== null && r.windows.status !== "sensitive" && r.outliers.status !== "sensitive";
}
function allRobust(r) {
  return r !== null && r.windows.status === "robust" && r.outliers.status === "robust" && r.placebo.status === "robust";
}
function verdict(d, r, a, estimatePresent) {
  const path = [];
  const reliable = baselineReliable(d, r, estimatePresent);
  const robust = allRobust(r);
  path.push(`sufficiency=${d.sufficiency}`);
  if (d.sufficiency === "too-early") return decide("too-early", path);
  path.push(`identification=${d.identification}`);
  if (d.identification === "none") return decide("no-estimate", path);
  path.push(`estimatePresent=${estimatePresent}`);
  if (!estimatePresent) return decide("before-after-only", path);
  path.push(`explainsAsWell=${a.explainsAsWell}`);
  if (a.explainsAsWell) return decide("alternative-explains", path);
  path.push(`effect=${d.effect}`);
  if (d.effect === "uncertain") return decide("interval-includes-zero", path);
  if (d.effect === "near-zero") {
    path.push(`baselineReliable=${reliable}`);
    if (!reliable) return decide("near-zero-unreliable-baseline", path);
    path.push(`effectBasis=${d.effectBasis}`);
    if (d.effectBasis === "threshold") return decide("near-zero-precise", path);
    if (d.effectBasis === "noise") return decide("near-zero-noise", path);
    return decide("near-zero-unreliable-baseline", path);
  }
  path.push(`oppositeDirection=${d.oppositeDirection}`);
  if (d.oppositeDirection) {
    path.push(`identification=${d.identification}`);
    return decide(
      atLeastModerate2(d.identification) ? "opposite-direction" : "opposite-direction-weak",
      path
    );
  }
  path.push(`thresholdState=${d.thresholdState}`);
  if (d.thresholdState === "clearly-below") {
    path.push(`baselineReliable=${reliable}`);
    if (reliable) return decide("below-threshold-precise", path);
  }
  path.push(`identification=${d.identification}`);
  if (d.identification === "weak") return decide("weak-identification", path);
  path.push(`inStatedDirection=${d.inStatedDirection}`);
  path.push(`materiality=${d.materiality}`);
  if (d.materiality === "not-assessed") {
    path.push(`materialityReason=${d.materialityReason}`);
    return decide(
      d.materialityReason === "pre-level-near-zero" ? "threshold-not-applicable" : "no-threshold",
      path
    );
  }
  path.push(`thresholdState=${d.thresholdState}`);
  if (d.thresholdState === "possibly-below") return decide("threshold-not-settled", path);
  path.push(`targetState=${d.targetState}`);
  if (d.targetState === "missed") return decide("below-target", path);
  if (d.targetState === "not-settled") return decide("target-not-settled", path);
  path.push(`allRobust=${robust}`);
  if (!robust) return decide("robustness", path);
  return decide("supported", path);
}

// src/engine/analyze.ts
var MIN_PRE_FOR_SPREAD = 2;
var DESCRIPTIVE_SD_MULTIPLE = 2;
function fail(message) {
  throw new RangeError(message);
}
function checkValues(periods, label) {
  for (const period of periods) {
    if (period.value !== null && !Number.isFinite(period.value)) {
      fail(`${label} holds a value that is not a finite number at index ${period.index}.`);
    }
  }
}
function checkPositive(label, value) {
  if (value !== void 0 && (!Number.isFinite(value) || value <= 0)) {
    fail(`${label} must be a finite positive number.`);
  }
}
function validate(series, question) {
  const n = series.periods.length;
  const T0 = question.changeIndex;
  if (!Number.isInteger(T0) || T0 < 1 || T0 > n - 1) {
    fail(`changeIndex must be an integer from 1 to ${n - 1}.`);
  }
  if (series.control !== null && series.control.length !== n) {
    fail("control must have one value per period.");
  }
  checkValues(series.periods, "periods");
  if (series.control !== null) {
    checkValues(series.control, "control");
  }
  const lag = question.lagPeriods;
  if (lag !== void 0 && (!Number.isInteger(lag) || lag < 0)) {
    fail("lagPeriods must be a non-negative integer.");
  }
  checkPositive("target", question.target);
  checkPositive("minimumMeaningful", question.minimumMeaningful);
  checkPositive("minimumMeaningfulAbsolute", question.minimumMeaningfulAbsolute);
}
function presentCount2(values, from, to) {
  let count = 0;
  const last = Math.min(to, values.length - 1);
  for (let t = Math.max(0, from); t <= last; t++) {
    if (values[t] !== null) {
      count++;
    }
  }
  return count;
}
function evaluationWindow(values, T0, Tb) {
  const n = values.length;
  const nPostIdx = Math.max(0, n - Tb);
  let W = Math.min(nPostIdx, Math.max(T0, MIN_POST), MAX_WINDOW);
  while (presentCount2(values, Tb, Tb + W - 1) < MIN_POST && Tb + W < n && W < MAX_WINDOW) {
    W++;
  }
  const reason = Tb + W >= n ? "all-post" : W === MAX_WINDOW ? "capped-at-max" : "capped-by-pre";
  return { start: Tb, length: W, reason };
}
function preValues(values, T0) {
  const present2 = [];
  for (let t = 0; t < Math.min(T0, values.length); t++) {
    const v = values[t];
    if (v !== null && v !== void 0) {
      present2.push(v);
    }
  }
  if (present2.length < MIN_PRE_FOR_SPREAD) {
    return { values: present2, mean: null, sd: null };
  }
  return { values: present2, mean: mean(present2), sd: sd(present2) };
}
function summarize(series, values, T0, window) {
  const n = values.length;
  const Tb = window.start;
  return {
    periods: n,
    pre: T0,
    prePresent: presentCount2(values, 0, T0 - 1),
    post: window.length,
    postPresent: presentCount2(values, Tb, Tb + window.length - 1),
    postPresentAll: presentCount2(values, Tb, n - 1),
    frequency: series.frequency,
    firstDate: series.periods[0]?.date ?? null,
    lastDate: series.periods[n - 1]?.date ?? null,
    name: series.name,
    hasControl: series.control !== null,
    unit: series.unit,
    currencySymbol: series.currencySymbol,
    normalizations: series.normalizations,
    gaps: series.gaps
  };
}
var UNFITTED_CONTROL = "The comparison group could not be fitted beside the treated series.";
function shortHistoryFallback(nPre, series) {
  return `Only ${formatCount(nPre)} ${unit(series.frequency, nPre)} came before the change; ${formatCount(MIN_PRE)} are needed.`;
}
function fit(series, values, question, summary, style) {
  const T0 = question.changeIndex;
  const L = question.lagPeriods;
  const W = question.window.length;
  const descriptive = beforeAfter(values, question, question.window);
  if (descriptive === null) {
    return { method: "none", descriptive: null, its: null, did: null, fallback: null };
  }
  const itsResult = its(values, T0, L, W, series.frequency);
  if (itsResult === null) {
    const fallback = summary.prePresent < MIN_PRE ? shortHistoryFallback(summary.prePresent, series) : null;
    return { method: "before-after", descriptive, its: null, did: null, fallback };
  }
  if (series.control === null) {
    return { method: "its", descriptive, its: itsResult, did: null, fallback: null };
  }
  const control = series.control.map((p) => p.value);
  const didResult = did(values, control, T0, L, W, series.frequency, style);
  if (didResult === null) {
    const usability = controlUsability(differenceSeries(values, control), T0, T0 + L, W, series.frequency);
    return { method: "its", descriptive, its: itsResult, did: null, fallback: usability.fallback ?? UNFITTED_CONTROL };
  }
  return { method: "did", descriptive, its: itsResult, did: didResult, fallback: null };
}
function analyze(series, question) {
  validate(series, question);
  const values = series.periods.map((p) => p.value);
  const T0 = question.changeIndex;
  const L = question.lagPeriods ?? 0;
  const Tb = T0 + L;
  const window = evaluationWindow(values, T0, Tb);
  const pre = preValues(values, T0);
  const threshold = resolveThreshold(question, pre.mean, pre.sd);
  const resolved = {
    changeIndex: T0,
    direction: question.direction,
    target: question.target ?? null,
    minimumMeaningful: question.minimumMeaningful ?? null,
    minimumMeaningfulAbsolute: question.minimumMeaningfulAbsolute ?? null,
    thresholdSource: threshold.source,
    lagPeriods: L,
    metricName: name(series, question),
    window,
    postPeriods: Math.max(0, values.length - Tb)
  };
  const summary = summarize(series, values, T0, window);
  const style = { unit: series.unit, currencySymbol: series.currencySymbol };
  const g = question.direction === "up" ? 1 : -1;
  const fitted = fit(series, values, resolved, summary, style);
  const estimate = fitted.did?.estimate ?? fitted.its?.estimate ?? null;
  const treatedIts = fitted.its?.estimate ?? null;
  const headlineFit = fitted.did !== null ? { method: "did", fit: fitted.did.fit } : fitted.its !== null ? { method: "its", fit: fitted.its.fit } : null;
  const measured = fitted.did?.difference ?? values;
  const placeboResult = estimate === null || headlineFit === null ? null : placebo({
    values: measured,
    method: estimate.method,
    T0,
    Tb,
    W: window.length,
    season: fitted.its?.fit.season ?? null,
    noiseSd: estimate.noiseSd,
    direction: question.direction,
    interval: estimate.interval,
    mAbs: threshold.mAbs,
    frequency: series.frequency
  });
  const checks = estimate === null || headlineFit === null ? null : robustness({
    headline: headlineFit,
    values: measured,
    periods: series.periods,
    frequency: series.frequency,
    style,
    mAbs: threshold.mAbs,
    noiseSd: estimate.noiseSd,
    g,
    placebo: placeboResult
  });
  const alternative = alternatives({
    series,
    question: resolved,
    estimate,
    its: fitted.its,
    descriptive: fitted.descriptive,
    outliers: checks?.outliers ?? null,
    mAbs: threshold.mAbs,
    noiseSd: estimate?.noiseSd ?? 0,
    g
  });
  const dims = dimensions({
    method: fitted.method,
    estimate,
    question: resolved,
    preMean: pre.mean,
    preSd: pre.sd,
    series: summary,
    robustness: checks,
    placebo: placeboResult,
    divergenceSentence: fitted.did?.divergenceSentence ?? null
  });
  const decision = verdict(dims, checks, alternative, estimate !== null);
  const percent = percentUnitsAvailable(pre.mean, pre.sd);
  const next = nextMeasurement({
    verdict: decision,
    dimensions: dims,
    alternative,
    robustness: checks,
    estimate,
    headline: headlineFit,
    question: resolved,
    series: summary,
    periods: series.periods,
    thresholdAbs: threshold.mAbs,
    targetAbs: resolved.target !== null && percent && pre.mean !== null ? resolved.target * pre.mean : null
  });
  const assembled = {
    series: summary,
    question: resolved,
    method: fitted.method,
    fallback: fitted.fallback,
    descriptive: fitted.descriptive,
    estimate,
    treatedIts,
    placebo: placeboResult,
    robustness: checks,
    alternative,
    dimensions: dims,
    verdict: decision,
    next
  };
  const language = {
    result: assembled,
    periods: series.periods,
    descriptiveHalfWidth: pre.sd === null ? null : DESCRIPTIVE_SD_MULTIPLE * pre.sd / Math.sqrt(pre.values.length)
  };
  return {
    ...assembled,
    headline: headline(language),
    details: details(language),
    chart: buildChart(
      series,
      resolved,
      fitted.its?.lines ?? null,
      fitted.did?.difference ?? null,
      placeboResult,
      estimate?.interval ?? null
    )
  };
}

// src/ledger/ledger.ts
var EMPTY_COUNTS = () => ({
  supported: 0,
  "partially-supported": 0,
  "not-supported": 0,
  inconclusive: 0,
  "too-early": 0
});
function entryFrom(result, input) {
  const q = result.question;
  const target = q.minimumMeaningful ?? q.target ?? null;
  const expected = input.expected === void 0 ? q.target ?? target : input.expected;
  const needed = result.next.kind === "wait" || result.next.kind === "more-post-periods" || result.next.kind === "keep-measuring" ? result.next.periods : null;
  return {
    id: input.id,
    name: input.name,
    loggedOn: input.today,
    changeDate: result.chart.periods[q.changeIndex]?.date ?? null,
    changeIndex: q.changeIndex,
    direction: q.direction,
    target,
    expected,
    metricName: result.series.name,
    frequency: result.series.frequency,
    verdict: result.verdict.word,
    headline: result.headline,
    effectPercent: result.estimate?.effectPercent ?? null,
    periodsAfter: result.series.postPresentAll,
    periodsNeeded: needed,
    lastChecked: input.today
  };
}
function refresh(entry, result, today) {
  const next = entryFrom(result, { id: entry.id, name: entry.name, today, expected: entry.expected });
  return { ...next, loggedOn: entry.loggedOn, target: entry.target };
}
function unitWord2(frequency, n) {
  const base2 = frequency === "weekly" ? "week" : frequency === "monthly" ? "month" : frequency === "daily" ? "day" : "period";
  return n === 1 ? base2 : `${base2}s`;
}
function summarize2(entries) {
  const counts = EMPTY_COUNTS();
  for (const e of entries) counts[e.verdict] += 1;
  const total = entries.length;
  const waiting = entries.filter((e) => e.verdict === "too-early" || e.verdict === "inconclusive" && e.periodsNeeded != null).slice().sort((a, b) => a.loggedOn.localeCompare(b.loggedOn)).map((e) => e.periodsNeeded != null ? `${e.name} needs ${e.periodsNeeded} more ${unitWord2(e.frequency, e.periodsNeeded)}.` : `${e.name} can't be told yet.`);
  let sentence;
  if (total === 0) sentence = "No changes logged yet.";
  else {
    const worked = counts.supported;
    const partly = counts["partially-supported"];
    const didNot = counts["not-supported"];
    const unclear = counts.inconclusive + counts["too-early"];
    const parts = [];
    if (worked) parts.push(`${worked} worked`);
    if (partly) parts.push(`${partly} partly`);
    if (didNot) parts.push(`${didNot} did not`);
    if (unclear) parts.push(`${unclear} can't be told yet`);
    sentence = `${total} ${total === 1 ? "change" : "changes"} logged. ${parts.join(", ")}.`;
  }
  return { total, counts, sentence, waiting };
}
function median(xs) {
  const s = xs.slice().sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
function calibration(entries) {
  const pairs = entries.filter((e) => e.expected != null && e.expected > 0 && e.effectPercent != null && e.verdict !== "too-early").map((e) => {
    const sign2 = e.direction === "up" ? 1 : -1;
    return sign2 * e.effectPercent / e.expected;
  });
  if (pairs.length < 3) return { n: pairs.length, ratio: null, sentence: null };
  const ratio = median(pairs);
  let sentence;
  if (ratio >= 0.85 && ratio <= 1.15) sentence = `Across ${pairs.length} changes with an expectation, the measured effect ran close to what was expected.`;
  else if (ratio <= 0) sentence = `Across ${pairs.length} changes with an expectation, the typical measured effect went the other way from what was expected.`;
  else if (ratio < 1) sentence = `Across ${pairs.length} changes with an expectation, the measured effect ran about ${describeFraction(ratio)} of what was expected.`;
  else sentence = `Across ${pairs.length} changes with an expectation, the measured effect ran about ${ratio.toFixed(1)} times what was expected.`;
  return { n: pairs.length, ratio, sentence };
}
function describeFraction(r) {
  if (r < 0.2) return "a tenth";
  if (r < 0.3) return "a quarter";
  if (r < 0.42) return "a third";
  if (r < 0.6) return "half";
  if (r < 0.72) return "two thirds";
  return "three quarters";
}
export {
  analyze,
  calibration,
  entryFrom,
  parse,
  refresh,
  summarize2 as summarize
};
