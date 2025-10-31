// FILE: pages/docs/index.tsx
import fs from 'fs';
import path from 'path';
import Link from 'next/link';

export default function DocsIndex({ files }: { files: string[] }) {
  return (
    <div className="mx-auto max-w-3xl p-6">
      <h1 className="text-2xl font-semibold mb-4">Docs</h1>
      <ul className="list-disc pl-6 space-y-2">
        {files.map((file) => {
          const slug = file.replace(/\.mdx?$/i, '').replace(/\s+/g, '-');
          return (
            <li key={file}>
              <Link className="text-blue-600 hover:underline" href={`/docs/${slug}`}>
                {file}
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export async function getStaticProps() {
  const docsDir = path.join(process.cwd(), 'docs');
  const all = fs.readdirSync(docsDir).filter((f) => /\.mdx?$/i.test(f));
  return { props: { files: all } };
}


