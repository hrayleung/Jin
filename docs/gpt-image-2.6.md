# GPT Image 2.6 in Jin

Choose **GPT Image 2.6 Flare** or **GPT Image 2.6 Sunburst** under the OpenAI provider. The OpenAI WebSocket provider also works through Jin’s existing HTTP image fallback. These are the exact IDs `gpt-image-2.6-flare` and `gpt-image-2.6-sunburst`; no dated aliases are assumed.

Open the chat’s **Image Generation** menu to configure the request. Settings are saved with the conversation.

| Control | Supported values |
| --- | --- |
| Complexity | Low, Medium, High; provider default High |
| Quality | Auto, Low, Medium, High, XHigh, Max |
| Count | 1–10; SVG always uses 1 |
| Raster size | Auto, suggested presets, or custom dimensions in 16-pixel steps; max edge 3840, aspect ratio at most 3:1, 655,360–8,294,400 pixels |
| Output | PNG, JPEG, WebP, SVG, GIF |
| Transparency | PNG or WebP |
| Compression | JPEG or WebP |
| Moderation | Auto or Low |
| GIF animation | 2–64 frames, 20–2,000 ms per frame, rounded to 10 ms; defaults 9 frames and 200 ms |

**Automatic input** edits current attachments, or reuses the most recent image when there are no new attachments. Choose **New Image** to start from a text prompt without reusing earlier images. Choose **Edit Images** to require an image input. Editing accepts PNG, JPEG and WebP, with up to 16 reference images.

## Markup and masks

1. Attach the original image first. Additional reference images can follow it.
2. Attach a separate PNG guide last. Its dimensions must match the first image after orientation.
3. In **Edit Guidance**, select **Last Image Is Markup** or **Last Image Is a Mask**.
4. Describe the change in the text prompt and send.

Markup is a transparent annotation layer, such as a circle around the object to change. It must contain transparent pixels; a flattened copy of the original is not a markup layer. The original and markup may each contain at most 16,777,216 pixels. The markup file is limited to 50 MB.

For a mask, use an original PNG and a matching PNG mask with an alpha channel. Transparent mask areas identify where to edit. A guide is sent separately from the reference images. Markup and mask modes are mutually exclusive. When a reference is a remote HTTPS URL, OpenAI validates dimensions that Jin cannot inspect locally.

## SVG and GIF

Select **SVG** for editable vector output or **GIF** for an animation. Both use new-image generation with a text prompt and no image attachments. They do not support image edits, output compression, prompt rewriting or partial-image streaming. Jin returns the finished output.

The **Animation…** sheet configures GIF frame count and duration. GIF custom dimensions must be positive multiples of 16; **Auto** lets OpenAI pick a suitable frame size. OpenAI also enforces a combined frame/count pixel budget that is not fully published. If it rejects a large request, reduce dimensions, frame count or image count.

SVG uses a native vector preview. GIF plays in the chat and respects the system’s Reduce Motion setting. Previews have bounded display/memory sizes; opening, dragging, copying and saving preserve the original SVG/GIF bytes. SVG and animated GIF are not accepted directly as edit inputs; export a PNG, JPEG or WebP first.

No context-window or output-token limit is invented for these image models. Configure image dimensions, quality and complexity instead.

## Scope and evidence

The Vercel-hosted `openai/gpt-image-2.6-*` entries remain catalog-only: its compatible adapter needs an Images transport, and the gateway’s public reference does not verify the new 2.6 controls. Native OpenAI support does not establish gateway support.

Verified against OpenAI’s [Flare model page](https://developers.openai.com/api/docs/models/gpt-image-2.6-flare), [Sunburst model page](https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst), and [image generation guide](https://developers.openai.com/api/docs/guides/image-generation), including the guide’s embedded GPT Image 2.6 size/quality calculator, on 2026-11-05. The generic Images API reference still enumerates older model versions in some sections, so exact 2.6 guide/model evidence takes precedence.
