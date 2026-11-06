/**
 * Wizard-AI Context Format Utilities
 *
 * 4-Layer Format Stack for token-optimized LLM context:
 *   Layer 4: JavaScript     → execution (pi-extensible-workflows sandbox)
 *   Layer 3: YAML           → orchestration (workflow descriptors, settings, role frontmatter)
 *   Layer 2: Markdown + LEA → content (instructions, memory, docs)
 *   Layer 1: JSON minified  → API boundaries (tool I/O only)
 *
 * Implements:
 *   - TOON (Token Oriented Object Notation) converter
 *   - LEA (Lossless Evidence Aliases) encoder/decoder
 *   - Markdown Table formatter
 *   - Context compressor (combines all formats)
 */

'use strict';

const { execFileSync } = require('node:child_process');

function runTOON(args, input) {
  return execFileSync(process.env.TOON_BIN || 'toon', args, {
    input,
    encoding: 'utf8',
  }).trimEnd();
}

// ============================================================================
// TOON — Token Oriented Object Notation
// Reduces token usage by 40-75% vs JSON for uniform arrays of objects.
// Schema is declared once; rows contain only values.
// ============================================================================

/**
 * Convert an array of uniform objects to TOON format.
 *
 * Input:  [{ id: 1, name: "Alice", role: "admin" }, { id: 2, name: "Bob", role: "user" }]
 * Output: items[2]{id,name,role}:\n  1,Alice,admin\n  2,Bob,user
 *
 * @param {string} label - Name for the collection (e.g., "skills", "issues", "users")
 * @param {Array<Object>} items - Array of uniform objects
 * @param {Object} [options]
 * @param {string} [options.delimiter=','] - Value separator
 * @param {string[]} [options.fields] - Explicit field order (auto-detected if omitted)
 * @returns {string} TOON-formatted string
 */
function toTOON(label, items, options = {}) {
  if (!Array.isArray(items) || items.length === 0) return `${label}:\n(empty)`;
  return `${label}:\n${runTOON(['--encode'], JSON.stringify(items))}`;
}

/**
 * Convert a single object to TOON key-value format.
 * Removes JSON braces and quotes for flat objects.
 *
 * @param {string} label - Object name
 * @param {Object} obj - Object to convert
 * @returns {string} TOON-formatted string
 */
function objToTOON(label, obj) {
  if (!obj || typeof obj !== 'object') return `${label}:\n(empty)`;
  return `${label}:\n${runTOON(['--encode'], JSON.stringify(obj))}`;
}

/**
 * Parse TOON array format back to JSON objects.
 *
 * @param {string} toonStr - TOON-formatted string
 * @returns {{ label: string, items: Object[] | Object }}
 */
function fromTOON(toonStr) {
  const lines = toonStr.trim().split('\n');
  let label = 'unknown';
  if (lines[0] && lines[0].endsWith(':')) {
    label = lines[0].slice(0, -1);
    lines.shift();
  }
  const decoded = JSON.parse(runTOON(['--decode'], lines.join('\n')));
  return { label, items: decoded };
}


// ============================================================================
// LEA — Lossless Evidence Aliases
// Defines sources once, references them with short IDs.
// Saves 60-80% on repeated metadata in evidence-heavy workflows.
// ============================================================================

/**
 * Encode sources and evidence into LEA format.
 *
 * @param {Object} config
 * @param {Object<string, string>} config.sources - Source dictionary { "S1": "MEMORY.md", "S2": "PROJECT_STATUS.md" }
 * @param {Array<{ id: string, source: string, content: string }>} config.evidence - Evidence entries
 * @param {string} [config.instruction] - Analysis instruction
 * @returns {string} LEA-formatted Markdown string
 */
function encodeLEA({ sources, evidence, instruction }) {
  const parts = [];

  // Source Dictionary
  parts.push('### SOURCE DICTIONARY');
  for (const [alias, name] of Object.entries(sources)) {
    parts.push(`[${alias}]: ${name}`);
  }

  // Evidence Table
  parts.push('');
  parts.push('### EVIDENCE TABLE');
  parts.push('| ID | Source | Content |');
  parts.push('|---|---|---|');
  for (const entry of evidence) {
    // Truncate content to prevent single-cell overflow
    const content = entry.content.length > 200
      ? entry.content.slice(0, 197) + '...'
      : entry.content;
    // Escape pipes in content
    const safeContent = content.replace(/\|/g, '\\|').replace(/\n/g, ' ');
    parts.push(`| ${entry.id} | [${entry.source}] | ${safeContent} |`);
  }

  // Instruction
  if (instruction) {
    parts.push('');
    parts.push('### INSTRUCTION');
    parts.push(instruction);
  }

  return parts.join('\n');
}

/**
 * Auto-encode project files into LEA format.
 * Reads files, splits into evidence chunks, and generates aliases.
 *
 * @param {string} cwd - Project directory
 * @param {Object} [options]
 * @param {string[]} [options.files] - Files to include (default: MEMORY.md, PROJECT_STATUS.md)
 * @param {number} [options.maxChunkSize=300] - Max chars per evidence chunk
 * @param {number} [options.maxChunks=10] - Max evidence entries total
 * @returns {string} LEA-formatted string
 */
function autoEncodeLEA(cwd, options = {}) {
  const fsLocal = require('fs');
  const pathLocal = require('path');

  const files = options.files || ['MEMORY.md', 'PROJECT_STATUS.md', 'NOTES.md'];
  const maxChunkSize = options.maxChunkSize || 300;
  const maxChunks = options.maxChunks || 10;

  const sources = {};
  const evidence = [];
  let evidenceId = 1;
  let sourceId = 1;

  for (const file of files) {
    const filePath = pathLocal.join(cwd, file);
    let content;
    try {
      content = fsLocal.readFileSync(filePath, 'utf-8');
    } catch {
      continue; // Skip missing files
    }

    const sKey = `S${sourceId++}`;
    sources[sKey] = file;

    // Split content into sections by headers
    const sections = content.split(/^#{1,3}\s+/m).filter(Boolean);

    for (const section of sections) {
      if (evidenceId > maxChunks) break;
      const trimmed = section.trim().slice(0, maxChunkSize);
      if (trimmed.length < 20) continue; // Skip tiny sections

      evidence.push({
        id: `E${evidenceId++}`,
        source: sKey,
        content: trimmed,
      });
    }
  }

  return encodeLEA({
    sources,
    evidence,
    instruction: `Analyze using only the referenced evidence IDs. Cite [E#] for every claim. Use [S#] for source attribution.`,
  });
}


// ============================================================================
// Markdown Table — Token-Efficient Tabular Format
// 65% fewer tokens than JSON arrays for flat data.
// ============================================================================

/**
 * Convert an array of objects to a Markdown table.
 *
 * @param {Array<Object>} items - Array of uniform objects
 * @param {Object} [options]
 * @param {string[]} [options.columns] - Column order (auto-detected if omitted)
 * @param {Object<string, string>} [options.headers] - Custom header labels { fieldName: "Display Label" }
 * @returns {string} Markdown table string
 */
function toMarkdownTable(items, options = {}) {
  if (!Array.isArray(items) || items.length === 0) return '(empty table)';

  const columns = options.columns || Object.keys(items[0]);
  const headers = options.headers || {};

  const headerRow = '| ' + columns.map(c => headers[c] || c).join(' | ') + ' |';
  const separator = '|' + columns.map(() => '---|').join('');
  const rows = items.map(item => {
    return '| ' + columns.map(c => {
      const val = item[c];
      if (val === null || val === undefined) return '';
      if (typeof val === 'object') return JSON.stringify(val);
      return String(val).replace(/\|/g, '\\|');
    }).join(' | ') + ' |';
  });

  return [headerRow, separator, ...rows].join('\n');
}


// ============================================================================
// Context Compressor — Unified Format Pipeline
// Combines TOON, LEA, Markdown Tables for maximum token efficiency.
// ============================================================================

/**
 * Compress project context for LLM injection.
 * Applies the 4-Layer Format Stack to minimize token usage.
 *
 * @param {string} cwd - Project directory
 * @param {Object} [options]
 * @param {string} [options.format='lea'] - Output format: 'lea', 'toon', 'markdown', 'raw'
 * @param {number} [options.maxTokenBudget=500] - Approximate max token budget
 * @param {string[]} [options.files] - Files to include in context
 * @returns {string} Compressed context string
 */
function compressContext(cwd, options = {}) {
  const format = options.format || 'lea';

  switch (format) {
    case 'lea':
      return autoEncodeLEA(cwd, {
        files: options.files,
        maxChunks: Math.min(options.maxTokenBudget || 500, 15),
      });

    case 'toon': {
      const fsLocal = require('fs');
      const pathLocal = require('path');
      const files = options.files || ['MEMORY.md', 'PROJECT_STATUS.md'];
      const results = [];
      for (const file of files) {
        try {
          const content = fsLocal.readFileSync(pathLocal.join(cwd, file), 'utf-8');
          const lines = content.split('\n').filter(l => l.trim()).slice(0, 20);
          results.push({ file, preview: lines.join(' ').slice(0, 200) });
        } catch { /* skip */ }
      }
      return toTOON('context', results);
    }

    case 'markdown': {
      const fsLocal = require('fs');
      const pathLocal = require('path');
      const files = options.files || ['MEMORY.md', 'PROJECT_STATUS.md'];
      const results = [];
      for (const file of files) {
        try {
          const content = fsLocal.readFileSync(pathLocal.join(cwd, file), 'utf-8');
          results.push({ file, size: content.length, summary: content.slice(0, 150) });
        } catch { /* skip */ }
      }
      return toMarkdownTable(results, {
        columns: ['file', 'size', 'summary'],
        headers: { file: 'File', size: 'Size', summary: 'Summary' },
      });
    }

    default:
      return autoEncodeLEA(cwd, { files: options.files });
  }
}


// ============================================================================
// Token Estimator — Approximate token count for budget tracking
// ============================================================================

/**
 * Estimate token count for a string using the ~4 chars/token heuristic.
 * More accurate than nothing, less accurate than tiktoken.
 *
 * @param {string} text - Text to estimate
 * @returns {{ chars: number, estimatedTokens: number, format: string }}
 */
function estimateTokens(text) {
  if (!text) return { chars: 0, estimatedTokens: 0, format: 'empty' };
  const chars = text.length;
  // ~4 chars per token for English; ~3.5 for code
  const estimatedTokens = Math.ceil(chars / 3.7);
  return { chars, estimatedTokens, format: 'heuristic-3.7' };
}

/**
 * Compare token efficiency of different format encodings.
 *
 * @param {Array<Object>} data - Source data
 * @param {string} label - Collection label
 * @returns {{ json: number, toon: number, markdown: number, savings: Object }}
 */
function compareFormats(data, label) {
  const jsonStr = JSON.stringify(data, null, 2);
  const jsonMinStr = JSON.stringify(data);
  const toonStr = toTOON(label, data);
  const mdStr = toMarkdownTable(data);

  const jsonTokens = estimateTokens(jsonStr).estimatedTokens;
  const jsonMinTokens = estimateTokens(jsonMinStr).estimatedTokens;
  const toonTokens = estimateTokens(toonStr).estimatedTokens;
  const mdTokens = estimateTokens(mdStr).estimatedTokens;

  return {
    json: jsonTokens,
    jsonMinified: jsonMinTokens,
    toon: toonTokens,
    markdown: mdTokens,
    savings: {
      toonVsJson: Math.round((1 - toonTokens / jsonTokens) * 100) + '%',
      toonVsJsonMin: Math.round((1 - toonTokens / jsonMinTokens) * 100) + '%',
      mdVsJson: Math.round((1 - mdTokens / jsonTokens) * 100) + '%',
    },
  };
}


// ============================================================================
// Exports
// ============================================================================

module.exports = {
  // TOON
  toTOON,
  objToTOON,
  fromTOON,

  // LEA (Lossless Evidence Aliases)
  encodeLEA,
  autoEncodeLEA,

  // Markdown Tables
  toMarkdownTable,

  // Context Compression
  compressContext,

  // Token Estimation
  estimateTokens,
  compareFormats,
};
