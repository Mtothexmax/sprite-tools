<script lang="ts">
	let { img = $bindable(null), hasImage = $bindable(false) } = $props();

	let canvas: HTMLCanvasElement = $state() as unknown as HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = $state(null);
	let fillActive = $state(false);
	let fillConnected = $state(true);
	let fillTolerance = $state(20);
	let canvasCursor = $state('default');
	let canUndo = $state(false);
	let canRedo = $state(false);
	let zoom = $state(1);
	let panX = $state(0), panY = $state(0);
	let isPanning = $state(false);
	let panStartX = 0, panStartY = 0;
	let showFeatherDlg = $state(false);
	let featherRadius = $state(1);
	let featherSnapshot: ImageData | null = null;

	const MAX_UNDO = 20;
	let undoStack: ImageData[] = [];
	let redoStack: ImageData[] = [];

	function saveState() {
		if (!ctx || !canvas) return;
		undoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		if (undoStack.length > MAX_UNDO) undoStack.shift();
		redoStack = [];
		canUndo = undoStack.length > 0;
		canRedo = false;
	}

	function restoreState(data: ImageData) {
		if (!ctx) return;
		canvas.width = data.width;
		canvas.height = data.height;
		ctx.putImageData(data, 0, 0);
	}

	function undo() {
		if (undoStack.length === 0 || !ctx || !canvas) return;
		redoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		const data = undoStack.pop()!;
		restoreState(data);
		canUndo = undoStack.length > 0;
		canRedo = true;
	}

	function redo() {
		if (redoStack.length === 0 || !ctx || !canvas) return;
		undoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		const data = redoStack.pop()!;
		restoreState(data);
		canUndo = true;
		canRedo = redoStack.length > 0;
	}

	function resetImage() {
		if (!img || !canvas) return;
		canvas.width = img.naturalWidth;
		canvas.height = img.naturalHeight;
		ctx = canvas.getContext('2d', { willReadFrequently: true })!;
		ctx.drawImage(img, 0, 0);
		fillActive = false;
		canvasCursor = 'default';
		undoStack = []; redoStack = [];
		canUndo = false; canRedo = false;
		zoom = 1; panX = 0; panY = 0;
	}

	$effect(() => {
		if (img && canvas) { resetImage(); saveState(); }
	});

	function getCanvasCoords(e: MouseEvent): { x: number; y: number } {
		const r = canvas.getBoundingClientRect();
		return {
			x: (e.clientX - r.left) * (canvas.width / r.width),
			y: (e.clientY - r.top) * (canvas.height / r.height)
		};
	}

	function getPixel(e: MouseEvent): { x: number; y: number; idx: number } | null {
		if (!ctx || !canvas) return null;
		const p = getCanvasCoords(e);
		const x = Math.round(p.x), y = Math.round(p.y);
		if (x < 0 || x >= canvas.width || y < 0 || y >= canvas.height) return null;
		return { x, y, idx: (y * canvas.width + x) * 4 };
	}

	function applyOp(fn: () => void) {
		saveState();
		fn();
	}

	function handleWheel(e: WheelEvent) {
		e.preventDefault();
		const r = canvas.getBoundingClientRect();
		const mx = e.clientX - r.left, my = e.clientY - r.top;
		const cx = mx / r.width * canvas.width;
		const cy = my / r.height * canvas.height;
		const delta = -e.deltaY * 0.001;
		const nz = Math.max(0.1, Math.min(20, zoom * (1 + delta)));
		panX = cx * zoom + panX - cx * nz;
		panY = cy * zoom + panY - cy * nz;
		zoom = nz;
	}

	function handleCanvasClick(e: MouseEvent) {
		const p = getPixel(e);
		if (!p || !ctx) return;
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		if (fillActive) {
			const [pr, pg, pb] = [data.data[p.idx], data.data[p.idx + 1], data.data[p.idx + 2]];
			const cx = p.x, cy = p.y;
			applyOp(() => fillToTransparent(pr, pg, pb, cx, cy, data));
		}
	}

	function fillToTransparent(pr: number, pg: number, pb: number, cx: number, cy: number, data: ImageData) {
		const d = data.data;
		const w = data.width, h = data.height;
		const maxDelta = fillTolerance * 2.55;
		const match = (idx: number) => {
			return Math.abs(d[idx] - pr) <= maxDelta && Math.abs(d[idx + 1] - pg) <= maxDelta && Math.abs(d[idx + 2] - pb) <= maxDelta;
		};
		if (!fillConnected) {
			for (let i = 0; i < d.length; i += 4) {
				if (match(i)) d[i + 3] = 0;
			}
		} else {
			const visited = new Uint8Array(w * h);
			const stack: [number, number][] = [[cx, cy]];
			if (!match((cy * w + cx) * 4)) return;
			visited[cy * w + cx] = 1;
			while (stack.length) {
				const [sx, sy] = stack.pop()!;
				d[(sy * w + sx) * 4 + 3] = 0;
				for (const [nx, ny] of [[sx - 1, sy], [sx + 1, sy], [sx, sy - 1], [sx, sy + 1]] as const) {
					if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
					const ni = ny * w + nx;
					if (visited[ni]) continue;
					visited[ni] = 1;
					if (match(ni * 4)) stack.push([nx, ny]);
				}
			}
		}
		ctx!.putImageData(data, 0, 0);
	}

	function startFill() {
		fillActive = true; updateCursor();
	}

	function updateCursor() {
		if (isPanning) { canvasCursor = 'grabbing'; return; }
		if (fillActive) { canvasCursor = 'crosshair'; return; }
		canvasCursor = 'default';
	}

	function handleMD(e: MouseEvent) {
		if (!hasImage || !canvas) return;
		if (e.button === 1) {
			e.preventDefault();
			isPanning = true;
			panStartX = e.clientX - panX;
			panStartY = e.clientY - panY;
			updateCursor();
			return;
		}
	}

	function handleMM(e: MouseEvent) {
		if (isPanning) {
			panX = e.clientX - panStartX;
			panY = e.clientY - panStartY;
			return;
		}
	}

	function handleMU() {
		if (isPanning) { isPanning = false; updateCursor(); }
	}

	function copyImage() {
		if (!canvas) return;
		canvas.toBlob(b => {
			if (!b) return;
			navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).catch(() => {});
		});
	}

	async function pasteImage() {
		if (!ctx || !canvas) return;
		try {
			const items = await navigator.clipboard.read();
			for (const item of items) {
				const blob = await item.getType('image/png').catch(() => null) || await item.getType('image/webp').catch(() => null);
				if (!blob) continue;
				const img2 = new Image();
				img2.onload = () => {
					applyOp(() => {
						canvas.width = img2.naturalWidth;
						canvas.height = img2.naturalHeight;
						ctx!.drawImage(img2, 0, 0);
					});
				};
				img2.src = URL.createObjectURL(blob);
				return;
			}
		} catch {}
	}

	function copyAlpha() {
		if (!ctx || !canvas) return;
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		const d = data.data;
		for (let i = 0; i < d.length; i += 4) {
			d[i] = d[i + 3]; d[i + 1] = d[i + 3]; d[i + 2] = d[i + 3]; d[i + 3] = 255;
		}
		const c = document.createElement('canvas');
		c.width = canvas.width; c.height = canvas.height;
		c.getContext('2d')!.putImageData(data, 0, 0);
		c.toBlob(b => {
			if (!b) return;
			navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).catch(() => {});
		});
	}

	async function pasteAlpha() {
		if (!ctx || !canvas) return;
		try {
			const items = await navigator.clipboard.read();
			for (const item of items) {
				const blob = await item.getType('image/png').catch(() => null) || await item.getType('image/webp').catch(() => null);
				if (!blob) continue;
				const img2 = new Image();
				img2.onload = () => {
					applyOp(() => {
						const c = document.createElement('canvas');
						c.width = img2.naturalWidth; c.height = img2.naturalHeight;
						const cx = c.getContext('2d')!;
						cx.drawImage(img2, 0, 0);
						const src = cx.getImageData(0, 0, c.width, c.height);
						const dst = ctx!.getImageData(0, 0, canvas!.width, canvas!.height);
						const sw = Math.min(c.width, canvas!.width);
						const sh = Math.min(c.height, canvas!.height);
						for (let y = 0; y < sh; y++) {
							for (let x = 0; x < sw; x++) {
								const si = (y * c.width + x) * 4;
								const di = (y * canvas!.width + x) * 4;
								const a = 0.299 * src.data[si] + 0.587 * src.data[si + 1] + 0.114 * src.data[si + 2];
								dst.data[di + 3] = Math.round(a);
							}
						}
						ctx!.putImageData(dst, 0, 0);
					});
				};
				img2.src = URL.createObjectURL(blob);
				return;
			}
		} catch {}
	}

	function saveImage() {
		if (!canvas) return;
		const a = document.createElement('a');
		a.href = canvas.toDataURL('image/png');
		a.download = 'image.png';
		a.click();
	}

	// Feather
	function openFeatherDlg() {
		if (!ctx || !canvas) return;
		featherSnapshot = ctx.getImageData(0, 0, canvas.width, canvas.height);
		featherRadius = 1;
		showFeatherDlg = true;
		featherPreview();
	}

	function findOpaque(sd: Uint8ClampedArray, w: number, h: number, ox: number, oy: number, r: number): [number, number, number] | null {
		for (let rr = 1; rr <= r; rr++) {
			for (let dy = -rr; dy <= rr; dy++) {
				for (let dx = -rr; dx <= rr; dx++) {
					if (Math.abs(dx) !== rr && Math.abs(dy) !== rr) continue;
					const nx = ox + dx, ny = oy + dy;
					if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
					const ni = (ny * w + nx) * 4;
					if (sd[ni + 3] === 255) return [sd[ni], sd[ni + 1], sd[ni + 2]];
				}
			}
		}
		return null;
	}

	function featherPreview() {
		if (!ctx || !canvas || !featherSnapshot) return;
		const sd = featherSnapshot.data;
		const w = featherSnapshot.width, h = featherSnapshot.height;
		const r = featherRadius;
		if (r < 1) { ctx.putImageData(featherSnapshot, 0, 0); return; }
		const shifted = new Uint8ClampedArray(sd);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const ci = (y * w + x) * 4;
				if (sd[ci + 3] === 0) continue;
				let minA = 255;
				for (let dy = -r; dy <= r; dy++) {
					for (let dx = -r; dx <= r; dx++) {
						const nx = x + dx, ny = y + dy;
						if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
						const a = sd[(ny * w + nx) * 4 + 3];
						if (a < minA) minA = a;
					}
				}
				shifted[ci + 3] = minA;
			}
		}
		const sigma = Math.max(r / 2, 0.5);
		const kw: number[] = [];
		let ksum = 0;
		for (let i = -r; i <= r; i++) { const w2 = Math.exp(-(i * i) / (2 * sigma * sigma)); kw.push(w2); ksum += w2; }
		for (let i = 0; i < kw.length; i++) kw[i] /= ksum;
		const tmp = new Float64Array(w * h);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				let a = 0;
				for (let kx = -r; kx <= r; kx++) a += shifted[((y * w + Math.min(w - 1, Math.max(0, x + kx))) * 4) + 3] * kw[kx + r];
				tmp[y * w + x] = a;
			}
		}
		const dst = new Uint8ClampedArray(sd);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const ci = (y * w + x) * 4;
				const sA = shifted[ci + 3];
				let hasTrans = false, hasOpaque = false;
				for (let dy = -r; dy <= r && !(hasTrans && hasOpaque); dy++) {
					for (let dx = -r; dx <= r && !(hasTrans && hasOpaque); dx++) {
						const nx = x + dx, ny = y + dy;
						if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
						const a = shifted[(ny * w + nx) * 4 + 3];
						if (a === 0) hasTrans = true;
						if (a === 255) hasOpaque = true;
					}
				}
				if (!hasTrans && sA === 255) continue;
				if (!hasOpaque && sA === 0) { dst[ci + 3] = 0; continue; }
				let a = 0;
				for (let ky = -r; ky <= r; ky++) a += tmp[Math.min(h - 1, Math.max(0, y + ky)) * w + x] * kw[ky + r];
				dst[ci + 3] = Math.min(255, Math.max(0, Math.round(a)));
				const c = findOpaque(sd, w, h, x, y, r);
				if (c) { dst[ci] = c[0]; dst[ci + 1] = c[1]; dst[ci + 2] = c[2]; }
			}
		}
		ctx.putImageData(new ImageData(dst, w, h), 0, 0);
	}

	function commitFeather() {
		if (!ctx || !canvas || !featherSnapshot) return;
		saveState();
		featherSnapshot = null;
		showFeatherDlg = false;
	}

	function cancelFeather() {
		if (!ctx || !canvas || !featherSnapshot) return;
		ctx.putImageData(featherSnapshot, 0, 0);
		featherSnapshot = null;
		showFeatherDlg = false;
	}
</script>

<div class="flex flex-col gap-4 h-full">
	{#if !hasImage}
		<div class="flex flex-col items-center justify-center h-full text-neutral-500 select-none py-16">
			<span class="material-icons text-5xl mb-2">image</span>
			<p class="text-sm">Open a spritesheet image to begin</p>
		</div>
	{:else}
		<div class="flex items-center gap-2 flex-wrap">
			<button onclick={saveImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">download</span>
				Save Image
			</button>
			<button onclick={copyImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">content_copy</span>
				Copy Image
			</button>
			<button onclick={pasteImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">content_paste</span>
				Paste Image
			</button>
			<button onclick={copyAlpha}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">opacity</span>
				Copy Alpha
			</button>
			<button onclick={pasteAlpha}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">invert_colors</span>
				Paste Alpha
			</button>
			<span class="w-px h-5 bg-neutral-600"></span>
			<button onclick={startFill}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer {fillActive ? 'bg-green-700 ring-2 ring-green-400' : 'bg-neutral-700 hover:bg-neutral-600'}">
				<span class="material-icons text-sm">format_paint</span>
				Fill
			</button>
			<label class="flex items-center gap-1 text-xs text-neutral-400 cursor-pointer select-none">
				<input type="checkbox" bind:checked={fillConnected}
					class="accent-blue-500 w-3 h-3" />
				Connected
			</label>
			<div class="flex items-center gap-2 text-xs text-neutral-400">
				<input type="range" min="0" max="100" bind:value={fillTolerance}
					class="w-20 accent-blue-500" />
				<span class="w-8 text-right font-mono text-neutral-300">{fillTolerance}%</span>
			</div>
			<span class="w-px h-5 bg-neutral-600"></span>
			<button onclick={openFeatherDlg}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">blur_on</span>
				Feather
			</button>
			{#if zoom !== 1}
				<span class="text-xs text-neutral-600">{Math.round(zoom * 100)}%</span>
			{/if}
			<div class="ml-auto flex items-center gap-1">
				<button onclick={undo} disabled={!canUndo}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-30 cursor-pointer disabled:cursor-not-allowed">
					<span class="material-icons text-sm">undo</span>
				</button>
				<button onclick={redo} disabled={!canRedo}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-30 cursor-pointer disabled:cursor-not-allowed">
					<span class="material-icons text-sm">redo</span>
				</button>
				<button onclick={resetImage}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
					<span class="material-icons text-sm">restart_alt</span>
					Reset
				</button>
			</div>
		</div>
		<div role="none" class="flex-1 overflow-hidden border border-neutral-700 rounded relative select-none"
			style="background-color:#1a1a1a;background-image:linear-gradient(45deg,#2a2a2a 25%,transparent 25%,transparent 75%,#2a2a2a 75%),linear-gradient(45deg,#2a2a2a 25%,transparent 25%,transparent 75%,#2a2a2a 75%);background-size:16px 16px;background-position:0 0,8px 8px;"
			onwheel={(e) => { if (hasImage) e.preventDefault(); }}
			onmousedown={(e) => { if (e.button === 1) { e.preventDefault(); isPanning = true; panStartX = e.clientX - panX; panStartY = e.clientY - panY; updateCursor(); } }}
			onmousemove={(e) => { if (isPanning) { panX = e.clientX - panStartX; panY = e.clientY - panStartY; } }}
			onmouseup={() => { if (isPanning) { isPanning = false; updateCursor(); } }}
			onmouseleave={() => { if (isPanning) { isPanning = false; updateCursor(); } }}
		>
			<canvas bind:this={canvas}
				class="block"
				style="transform-origin:0 0;transform:translate({panX}px,{panY}px) scale({zoom});image-rendering:pixelated;cursor:{canvasCursor}"
				onwheel={handleWheel}
				onclick={handleCanvasClick}
				aria-label="Background removal canvas"
			></canvas>
		</div>
	{/if}
</div>

{#if showFeatherDlg}
	<div role="presentation" class="fixed inset-0 z-50 flex items-start justify-center pt-12" onclick={cancelFeather} onkeydown={(e) => e.key === 'Escape' && cancelFeather()}>
		<div role="presentation" onclick={(e) => e.stopPropagation()}
			class="bg-neutral-800 border border-neutral-700 rounded-lg shadow-xl p-5 flex flex-col gap-4 w-72"
		>
			<div class="flex items-center justify-between">
				<span class="text-sm font-semibold text-white">Feather</span>
				<button onclick={cancelFeather} class="text-neutral-500 hover:text-white cursor-pointer">
					<span class="material-icons text-sm">close</span>
				</button>
			</div>
			<div class="flex flex-col gap-3">
				<div>
					<div class="flex items-center justify-between text-xs text-neutral-300 mb-1">
						<span>Inward</span>
						<span class="text-sm font-mono text-white">{featherRadius}px</span>
					</div>
					<input type="range" min="0" max="10" value={featherRadius}
						oninput={(e) => { featherRadius = parseInt((e.target as HTMLInputElement).value); featherPreview(); }}
						class="w-full accent-blue-500" />
				</div>
			</div>
			<div class="flex justify-end gap-2">
				<button onclick={cancelFeather}
					class="px-3 py-1.5 rounded text-xs bg-neutral-700 hover:bg-neutral-600 cursor-pointer text-white">
					Cancel
				</button>
				<button onclick={commitFeather}
					class="px-3 py-1.5 rounded text-xs bg-blue-700 hover:bg-blue-600 cursor-pointer text-white">
					OK
				</button>
			</div>
		</div>
	</div>
{/if}