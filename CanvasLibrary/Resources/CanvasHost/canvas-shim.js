/**
 * Resolves `import { … } from 'cursor/canvas'` after mountCanvas assigns
 * the runtime component exports onto globalThis.
 */
const g = globalThis;

function grab(name) {
  const value = g[name];
  if (typeof value === "undefined") {
    console.warn(`[canvas-shim] missing export: ${name}`);
  }
  return value;
}

export const Badge = grab("Badge");
export const BarChart = grab("BarChart");
export const Button = grab("Button");
export const Callout = grab("Callout");
export const Card = grab("Card");
export const CardBody = grab("CardBody");
export const CardHeader = grab("CardHeader");
export const Checkbox = grab("Checkbox");
export const Chip = grab("Chip");
export const Code = grab("Code");
export const CollapsibleSection = grab("CollapsibleSection");
export const DiffStats = grab("DiffStats");
export const DiffView = grab("DiffView");
export const Divider = grab("Divider");
export const Grid = grab("Grid");
export const H1 = grab("H1");
export const H2 = grab("H2");
export const H3 = grab("H3");
export const IconButton = grab("IconButton");
export const LineChart = grab("LineChart");
export const Link = grab("Link");
export const PieChart = grab("PieChart");
export const Pill = grab("Pill");
export const Row = grab("Row");
export const Select = grab("Select");
export const Spacer = grab("Spacer");
export const Stack = grab("Stack");
export const Stat = grab("Stat");
export const Swatch = grab("Swatch");
export const Table = grab("Table");
export const Tag = grab("Tag");
export const Text = grab("Text");
export const TextArea = grab("TextArea");
export const TextInput = grab("TextInput");
export const TodoList = grab("TodoList");
export const TodoListCard = grab("TodoListCard");
export const Toggle = grab("Toggle");
export const UsageBar = grab("UsageBar");

export const canvasPaletteDark = grab("canvasPaletteDark");
export const canvasPaletteLight = grab("canvasPaletteLight");
export const canvasTokens = grab("canvasTokens");
export const canvasTokensLight = grab("canvasTokensLight");
export const categoryPaletteDark = grab("categoryPaletteDark");
export const categoryPaletteLight = grab("categoryPaletteLight");
export const colorPalette = grab("colorPalette");
export const computeDAGLayout = grab("computeDAGLayout");
export const mergeStyle = grab("mergeStyle");
export const usageColorSequence = grab("usageColorSequence");
export const useCanvasAction = grab("useCanvasAction");
export const useCanvasState = grab("useCanvasState");
export const useHostTheme = grab("useHostTheme");
