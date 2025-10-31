// FILE: pages/docs/[slug].tsx
import path from 'path';
import Link from 'next/link';
import { GetStaticPaths, GetStaticProps } from 'next';
import { Markdown } from '../../components/Markdown';
import { listMarkdownFiles, loadMarkdownBySlug } from '../../lib/markdown';

type Props = {
  slug: string;
  html: string;
  title?: string;
};

export default function DocPage({ slug, html, title }: Props) {
  return (
    <div className="mx-auto max-w-3xl p-6">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold">{title || slug}</h1>
        <Link className="text-blue-600 hover:underline" href="/docs">← Back to Docs</Link>
      </div>
      <Markdown html={html} />
    </div>
  );
}

export const getStaticPaths: GetStaticPaths = async () => {
  const docsDir = path.join(process.cwd(), 'docs');
  const files = listMarkdownFiles(docsDir);
  const paths = files.map((f) => ({ params: { slug: f.replace(/\.mdx?$/i, '').replace(/\s+/g, '-') } }));
  return { paths, fallback: false };
};

export const getStaticProps: GetStaticProps = async (ctx) => {
  const slug = String(ctx.params?.slug || '');
  const docsDir = path.join(process.cwd(), 'docs');
  const doc = await loadMarkdownBySlug(docsDir, slug);
  const title = typeof doc.data.title === 'string' ? (doc.data.title as string) : undefined;
  return { props: { slug, html: doc.contentHtml, title } };
};


