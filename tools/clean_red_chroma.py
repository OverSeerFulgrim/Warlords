from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def connected_components(mask: np.ndarray, minimum_size: int) -> np.ndarray:
    height, width = mask.shape
    flat = mask.ravel()
    visited = np.zeros(flat.shape, dtype=np.bool_)
    remove = np.zeros(flat.shape, dtype=np.bool_)

    for start in np.flatnonzero(flat & ~visited):
        if visited[start]:
            continue
        queue: deque[int] = deque([int(start)])
        visited[start] = True
        component: list[int] = []
        while queue:
            index = queue.popleft()
            component.append(index)
            row, column = divmod(index, width)
            if column and flat[index - 1] and not visited[index - 1]:
                visited[index - 1] = True
                queue.append(index - 1)
            if column + 1 < width and flat[index + 1] and not visited[index + 1]:
                visited[index + 1] = True
                queue.append(index + 1)
            if row and flat[index - width] and not visited[index - width]:
                visited[index - width] = True
                queue.append(index - width)
            if row + 1 < height and flat[index + width] and not visited[index + width]:
                visited[index + width] = True
                queue.append(index + width)
        if len(component) >= minimum_size:
            remove[np.asarray(component, dtype=np.int64)] = True

    return remove.reshape(height, width)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--minimum-size", type=int, default=20000)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    pixels = np.asarray(image).copy()
    red = pixels[..., 0].astype(np.int16)
    green = pixels[..., 1].astype(np.int16)
    blue = pixels[..., 2].astype(np.int16)

    # The generated key varies slightly across the canvas. Select a broad
    # red-dominant family, then remove only large contiguous fields so small
    # intentional red details (notably the health icon) remain intact.
    chroma_family = (
        (red >= 90)
        & (red >= green + 45)
        & (red >= blue + 35)
        & (green <= 105)
        & (blue <= 115)
    )
    removed = connected_components(chroma_family, args.minimum_size)
    pixels[removed, 3] = 0

    # Clear RGB in fully transparent pixels to prevent colored mip-map halos.
    pixels[removed, 0:3] = 0
    Image.fromarray(pixels, "RGBA").save(args.output)
    print(f"Wrote {args.output}")
    print(f"Transparent pixels: {int(np.count_nonzero(pixels[..., 3] == 0))}/{pixels.shape[0] * pixels.shape[1]}")


if __name__ == "__main__":
    main()
