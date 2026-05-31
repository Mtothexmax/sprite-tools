<script lang="ts">
	interface FileEntry {
		file: File;
		img: HTMLImageElement | null;
		loaded: boolean;
	}

	interface PackedItem {
		entry: FileEntry;
		x: number; y: number;
		pw: number; ph: number;
		w: number; h: number;
	}

	let fileEntries: FileEntry[] = $state([]);
	let raster = $state(32);
	let packed: PackedItem[] | null = $state(null);
	let outW = $state(0);
	let outH = $state(0);
	let zoom = $state(1);
	let panX = $state(0), panY = $state(0);
	let isPanning = $state(false);
	let panStartX = 0, panStartY = 0;
	let previewCanvas = $state<HTMLCanvasElement>() as unknown as HTMLCanvasElement;
	let fileInput: HTMLInputElement;

	function addFiles() {
		fileInput.value = '';
		fileInput.click();
	}

	function onFileSelected() {
		const files = fileInput.files;
		if (!files) return;
		const batch: FileEntry[] = [];
		for (const f of files) {
			if (!f.type.startsWith('image/')) continue;
			const entry: FileEntry = { file: f, img: null, loaded: false };
			batch.push(entry);
			const reader = new FileReader();
			reader.onload = () => {
				const el = new Image();
				el.onload = () => {
					entry.loaded = true;
					const idx = fileEntries.findIndex(e => e.file === f);
					if (idx >= 0) fileEntries[idx] = { ...fileEntries[idx], img: el, loaded: true };
					if (batch.every(e => e.loaded)) doPack();
				};
				el.src = reader.result as string;
			};
			reader.readAsDataURL(f);
		}
		fileEntries = [...fileEntries, ...batch];
	}

	function removeFile(i: number) {
		fileEntries = fileEntries.filter((_, idx) => idx !== i);
		if (fileEntries.length === 0) {
			packed = null; outW = 0; outH = 0;
		} else if (fileEntries.every(e => e.loaded)) {
			doPack();
		}
	}

	function clearAll() {
		fileEntries = []; packed = null; outW = 0; outH = 0;
	}

	function triggerPack() {
		if (fileEntries.some(e => e.loaded)) doPack();
	}

	function handleWheel(e: WheelEvent) {
		e.preventDefault();
		if (!previewCanvas) return;
		const r = previewCanvas.getBoundingClientRect();
		const mx = e.clientX - r.left, my = e.clientY - r.top;
		const cx = mx / r.width * outW;
		const cy = my / r.height * outH;
		const delta = -e.deltaY * 0.001;
		const nz = Math.max(0.1, Math.min(20, zoom * (1 + delta)));
		panX = cx * zoom + panX - cx * nz;
		panY = cy * zoom + panY - cy * nz;
		zoom = nz;
	}

	function handleMD(e: MouseEvent) {
		if (e.button === 1) {
			e.preventDefault();
			isPanning = true;
			panStartX = e.clientX - panX;
			panStartY = e.clientY - panY;
		}
	}

	function handleMM(e: MouseEvent) {
		if (isPanning) {
			panX = e.clientX - panStartX;
			panY = e.clientY - panStartY;
		}
	}

	function handleMU() {
		isPanning = false;
	}

	function fitView() {
		if (!previewCanvas || outW === 0 || outH === 0) return;
		const parent = previewCanvas.parentElement;
		if (!parent) return;
		const pw = parent.clientWidth, ph = parent.clientHeight;
		if (pw === 0 || ph === 0) return;
		const zx = (pw - 16) / outW, zy = (ph - 16) / outH;
		zoom = Math.min(zx, zy, 1);
		panX = 0; panY = 0;
	}

	function doPack() {
		const valid = fileEntries.filter(e => e.loaded && e.img);
		if (valid.length === 0) { packed = null; outW = 0; outH = 0; return; }

		const items = valid.map(e => {
			const w = e.img!.naturalWidth;
			const h = e.img!.naturalHeight;
			const pw = Math.ceil(w / raster) * raster;
			const ph = Math.ceil(h / raster) * raster;
			return { entry: e, w, h, pw, ph, x: 0, y: 0 };
		});

		items.sort((a, b) => b.ph - a.ph || b.pw - a.pw);

		const totalArea = items.reduce((sum, i) => sum + i.pw * i.ph, 0);
		const maxItemDim = Math.max(...items.map(i => Math.max(i.pw, i.ph)), raster);
		let aw = Math.max(Math.ceil(Math.sqrt(totalArea) / raster) * raster, maxItemDim);

		let x = 0, y = 0, rowH = 0;
		for (const item of items) {
			if (x > 0 && x + item.pw > aw) {
				x = 0; y += rowH; rowH = 0;
			}
			if (item.pw > aw) aw = item.pw;
			item.x = x; item.y = y;
			x += item.pw;
			if (item.ph > rowH) rowH = item.ph;
		}
		const totalH = y + rowH;

		packed = items;
		outW = aw;
		outH = totalH;
		fitView();
	}

	$effect(() => {
		if (previewCanvas && packed && outW > 0 && outH > 0) {
			drawPreview();
			fitView();
		} else if (previewCanvas) {
			previewCanvas.width = 0;
			previewCanvas.height = 0;
		}
	});

	function drawPreview() {
		const c = previewCanvas;
		const ctx = c.getContext('2d', { willReadFrequently: true })!;
		c.width = outW;
		c.height = outH;

		for (let y = 0; y < outH; y += 8) {
			for (let x = 0; x < outW; x += 8) {
				const dark = (Math.floor(x / 8) + Math.floor(y / 8)) % 2 === 0;
				ctx.fillStyle = dark ? '#1e1e1e' : '#2a2a2a';
				ctx.fillRect(x, y, 8, 8);
			}
		}

		ctx.strokeStyle = 'rgba(255,255,255,0.06)';
		ctx.lineWidth = 1;
		for (let gx = 0; gx <= outW; gx += raster) { ctx.beginPath(); ctx.moveTo(gx + 0.5, 0); ctx.lineTo(gx + 0.5, outH); ctx.stroke(); }
		for (let gy = 0; gy <= outH; gy += raster) { ctx.beginPath(); ctx.moveTo(0, gy + 0.5); ctx.lineTo(outW, gy + 0.5); ctx.stroke(); }

		for (const item of packed!) {
			ctx.drawImage(item.entry.img!, item.x, item.y, item.w, item.h);
			ctx.strokeStyle = '#22c55e44';
			ctx.lineWidth = 1;
			ctx.strokeRect(item.x + 0.5, item.y + 0.5, item.w - 1, item.h - 1);
		}
	}

	function downloadPacked() {
		if (!packed || outW === 0 || outH === 0) return;
		const c = document.createElement('canvas');
		c.width = outW;
		c.height = outH;
		const ctx = c.getContext('2d')!;
		for (const item of packed) {
			ctx.drawImage(item.entry.img!, item.x, item.y, item.w, item.h);
		}
		c.toBlob(blob => {
			if (!blob) return;
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = url;
			a.download = 'tileset.png';
			a.click();
			URL.revokeObjectURL(url);
		}, 'image/png');
	}
</script>

<div class="flex flex-col gap-3 h-full">
	<div class="flex items-center gap-2 shrink-0 flex-wrap">
		<label for="raster-input" class="text-xs text-neutral-400 shrink-0">Raster:</label>
		<input id="raster-input" type="number" min="1" max="1024" bind:value={raster}
			oninput={triggerPack}
			class="w-16 px-2 py-1 rounded bg-neutral-800 border border-neutral-700 text-white text-sm" />
		<div class="flex gap-1">
			{#each [8, 16, 32, 64, 128] as v}
				<button onclick={() => { raster = v; triggerPack(); }}
					class="px-2 py-1 rounded text-xs {raster === v ? 'bg-blue-700 text-white' : 'bg-neutral-800 text-neutral-400 hover:text-white'} cursor-pointer transition-colors"
				>{v}</button>
			{/each}
		</div>
		<button onclick={addFiles}
			class="flex items-center gap-1 px-3 py-1.5 rounded text-sm bg-blue-700 hover:bg-blue-600 cursor-pointer transition-colors">
			<span class="material-icons text-sm">add</span>
			Add Files
		</button>
		{#if packed}
			<button onclick={downloadPacked}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm bg-green-700 hover:bg-green-600 cursor-pointer transition-colors">
				<span class="material-icons text-sm">download</span>
				Download PNG
			</button>
			<span class="text-xs text-neutral-500">{outW}×{outH}px &middot; {packed.length} item{packed.length !== 1 ? 's' : ''}</span>
			<span class="text-xs text-neutral-600">{Math.round(zoom * 100)}%</span>
		{/if}
	</div>

	<div class="flex gap-3 flex-1 min-h-0">
		<div class="w-56 flex flex-col gap-1 overflow-y-auto shrink-0">
			{#if fileEntries.length > 0}
				<div class="flex items-center gap-2 px-2 py-1 text-xs text-neutral-500">
					<span class="flex-1">{fileEntries.length} file{fileEntries.length !== 1 ? 's' : ''}</span>
					<button onclick={clearAll} class="text-neutral-500 hover:text-red-400 cursor-pointer transition-colors">
						<span class="material-icons text-sm">clear_all</span>
					</button>
				</div>
			{/if}
			{#each fileEntries as entry, i}
				<div class="flex items-center gap-2 px-2 py-1 rounded bg-neutral-800 text-xs">
					{#if entry.loaded && entry.img}
						<img src={entry.img.src} alt="" class="w-6 h-6 object-contain shrink-0" />
						<span class="flex-1 truncate" title={entry.file.name}>{entry.file.name}</span>
						<span class="text-neutral-500 shrink-0">{entry.img.naturalWidth}×{entry.img.naturalHeight}</span>
					{:else}
						<div class="w-6 h-6 bg-neutral-700 rounded shrink-0"></div>
						<span class="flex-1 truncate">{entry.file.name}</span>
					{/if}
					<button onclick={() => removeFile(i)}
						class="text-neutral-500 hover:text-red-400 cursor-pointer transition-colors shrink-0">
						<span class="material-icons text-sm">close</span>
					</button>
				</div>
			{:else}
				<div class="text-xs text-neutral-500 p-2">No files added yet.</div>
			{/each}
		</div>

		<div role="none" class="flex-1 overflow-hidden border border-neutral-700 rounded relative select-none bg-neutral-950"
			style="background-image:linear-gradient(45deg,#1e1e1e 25%,transparent 25%,transparent 75%,#1e1e1e 75%),linear-gradient(45deg,#1e1e1e 25%,transparent 25%,transparent 75%,#1e1e1e 75%);background-size:16px 16px;background-position:0 0,8px 8px;"
			onwheel={(e) => { if (packed) e.preventDefault(); }}
			onmousedown={handleMD}
			onmousemove={handleMM}
			onmouseup={handleMU}
			onmouseleave={handleMU}
		>
			{#if packed && outW > 0}
				<canvas bind:this={previewCanvas}
					class="block"
					style="transform-origin:0 0;transform:translate({panX}px,{panY}px) scale({zoom});image-rendering:pixelated;"
					onwheel={handleWheel}
				></canvas>
			{:else if fileEntries.length > 0}
				<div class="flex items-center justify-center h-full text-xs text-neutral-500">Loading images...</div>
			{:else}
				<div class="flex items-center justify-center h-full text-xs text-neutral-500">Add files to begin</div>
			{/if}
		</div>
	</div>

	<input type="file" accept="image/*" multiple bind:this={fileInput} onchange={onFileSelected} class="hidden" />
</div>
