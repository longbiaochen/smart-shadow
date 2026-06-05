export function extractFeishuText(content: unknown): string {
  if (typeof content !== "string") return "";
  try {
    const parsed = JSON.parse(content);
    if (typeof parsed.text === "string") return parsed.text;
    if (typeof parsed.content === "string") return parsed.content;
    if (Array.isArray(parsed.elements)) return flattenPostElements(parsed.elements);
  } catch {
    return content;
  }
  return "";
}

function flattenPostElements(elements: unknown[]): string {
  const chunks: string[] = [];
  for (const row of elements) {
    if (!Array.isArray(row)) continue;
    for (const item of row) {
      if (item && typeof item === "object" && "text" in item && typeof item.text === "string") {
        chunks.push(item.text);
      }
    }
  }
  return chunks.join("");
}
