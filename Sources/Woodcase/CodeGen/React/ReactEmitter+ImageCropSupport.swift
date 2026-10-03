//
//  ReactEmitter+ImageCropSupport.swift
//  Woodcase
//

extension ReactEmitter {
    /// `lib/PenImageCrop.tsx`: the component that draws an image paint through Pen's crop,
    /// emitted only when a file uses it (``EmitContext/usesImageCrop``).
    ///
    /// The crop box of a cover or contain crop takes the *cropped* image's aspect — its sides
    /// are the crop square's axes mapped back into the image, in pixels
    /// (``PenImagePlacement/cropBoxSize(imageSize:crop:)``) — so it depends on the image's
    /// own size. The generator never reads the image (a remote one, or one an image prop
    /// swaps in, is not known until the page runs), so the component measures it once per
    /// URL and draws with an `<svg>` whose `viewBox` is the crop box: `preserveAspectRatio`
    /// then covers (`slice`) or fits (`meet`) the box, centered, for any box size, exactly
    /// as ``PenImagePlacement`` places it. The image is the viewBox's unit square mapped
    /// through the crop; contain clips to the crop box with a nested `<svg>`. A stretch crop
    /// needs no size and draws at once. While it measures, the element is hidden and marked
    /// `data-pen-image="loading"`, which the render harness waits on.
    static let imageCropSupportFile = GeneratedFile(path: "lib/PenImageCrop.tsx", content: """
    import { useEffect, useState } from "react";

    /** The natural sizes already measured, by URL. */
    const penImageSizes = new Map<string, { width: number; height: number }>();

    /**
     * An image paint drawn through Pen's crop (format 2.20), filling the positioned
     * element it is placed in — or, with `frame`, the rect `[x, y, width, height]` of the
     * SVG pattern it is placed in.
     *
     * `crop` maps the image's unit square to the crop box's, as `[a, b, c, d, tx, ty]`.
     * With `stretch` the crop box is the box; with `cover` and `contain` it takes the
     * cropped image's aspect, scaled to cover or fit the box and centered. Only `contain`
     * clips to the crop box. A cover crop arrives already kept inside the image.
     */
    export function PenImageCrop({ href, placement, crop, frame }: {
      href: string;
      placement: "stretch" | "cover" | "contain";
      crop: [number, number, number, number, number, number];
      frame?: [number, number, number, number];
    }) {
      const [measured, setMeasured] = useState<{ href: string; width: number; height: number } | null>(null);
      const [drawn, setDrawn] = useState<string | null>(null);
      useEffect(() => {
        if (placement === "stretch") return;
        const known = penImageSizes.get(href);
        if (known) {
          setMeasured({ href, ...known });
          return;
        }
        let live = true;
        const probe = new Image();
        probe.onload = () => {
          const size = { width: probe.naturalWidth, height: probe.naturalHeight };
          penImageSizes.set(href, size);
          if (live) setMeasured({ href, ...size });
        };
        probe.onerror = () => {
          if (live) setMeasured({ href, width: 0, height: 0 });
        };
        probe.src = href;
        return () => {
          live = false;
        };
      }, [href, placement]);

      const [a, b, c, d, tx, ty] = crop;
      let width = 1;
      let height = 1;
      let sized = placement === "stretch";
      if (!sized && measured?.href === href) {
        // The crop square's axes mapped back into the image, in pixels.
        const det = a * d - b * c;
        width = Math.hypot((d / det) * measured.width, (-b / det) * measured.height);
        height = Math.hypot((-c / det) * measured.width, (a / det) * measured.height);
        sized = width > 0 && height > 0 && Number.isFinite(width) && Number.isFinite(height);
        if (!sized) return null;
      }
      const settled = sized && drawn === href;
      const image = (
        <image
          href={href}
          width={1}
          height={1}
          preserveAspectRatio="none"
          transform={`matrix(${width * a} ${height * b} ${width * c} ${height * d} ${width * tx} ${height * ty})`}
          onLoad={() => setDrawn(href)}
          onError={() => setDrawn(href)}
        />
      );
      const [x, y, w, h] = frame ?? [0, 0, "100%", "100%"];
      const visibility = sized ? "visible" : "hidden";
      return (
        <svg
          aria-hidden="true"
          data-pen-image={settled ? "ready" : "loading"}
          x={x}
          y={y}
          width={w}
          height={h}
          viewBox={`0 0 ${width} ${height}`}
          preserveAspectRatio={placement === "stretch" ? "none" : placement === "cover" ? "xMidYMid slice" : "xMidYMid meet"}
          overflow="visible"
          style={frame
            ? { overflow: "visible", visibility }
            : { position: "absolute", inset: 0, overflow: "visible", visibility }}
        >
          {placement === "contain" ? <svg width={width} height={height} overflow="hidden">{image}</svg> : image}
        </svg>
      );
    }

    """)
}
