// FILE: components/Markdown.tsx
import React from 'react';

export function Markdown({ html }: { html: string }) {
  return (
    <div className="prose prose-zinc max-w-none" dangerouslySetInnerHTML={{ __html: html }} />
  );
}


