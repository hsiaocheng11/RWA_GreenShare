// FILE: lib/markdown.ts
import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { remark } from 'remark';
import html from 'remark-html';

export type MarkdownDoc = {
  slug: string;
  contentHtml: string;
  data: Record<string, unknown>;
};

export function listMarkdownFiles(dir: string): string[] {
  return fs.readdirSync(dir).filter((f) => /\.mdx?$/i.test(f));
}

export async function loadMarkdownBySlug(dir: string, slug: string): Promise<MarkdownDoc> {
  const candidates = listMarkdownFiles(dir);
  const match = candidates.find((f) => f.replace(/\.mdx?$/i, '').replace(/\s+/g, '-') === slug);
  if (!match) {
    throw new Error(`Markdown not found for slug: ${slug}`);
  }
  const fullPath = path.join(dir, match);
  const fileContents = fs.readFileSync(fullPath, 'utf8');
  const { content, data } = matter(fileContents);
  const processed = await remark().use(html).process(content);
  return {
    slug,
    contentHtml: processed.toString(),
    data,
  };
}


