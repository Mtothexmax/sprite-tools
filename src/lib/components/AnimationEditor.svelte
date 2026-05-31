<script lang="ts">
	import { onMount } from 'svelte';
	import type { SpriteLabel } from '$lib/types';

	let { img = $bindable(null), labels = $bindable([]), hasImage = $bindable(false) } = $props();

	interface TimelineFrame {
		labelIndex: number;
		duration: number;
	}

	let timeline: TimelineFrame[] = $state([]);
	let currentFrame = $state(0);
	let isPlaying = $state(false);
	let playTimer: number | null = null;
	let previewCanvas: HTMLCanvasElement = $state() as unknown as HTMLCanvasElement;
	let previewCtx: CanvasRenderingContext2D | null = $state(null);
	let dragIndex: number | null = $state(null);
	let dropIndex: number | null = $state(null);
	let addLabelIndex = $state(0);
	let bulkDuration = $state('');

	const PREVIEW_W = 320;
	const PREVIEW_H = 320;

	function drawPreview() {
		if (!previewCtx || !img || timeline.length === 0) return;
		const entry = timeline[currentFrame];
		const label = labels[entry.labelIndex];
		if (!label) return;
		const s = Math.min(PREVIEW_W / label.width, PREVIEW_H / label.height);
		const dw = label.width * s, dh = label.height * s;
		const dx = (PREVIEW_W - dw) / 2, dy = (PREVIEW_H - dh) / 2;
		previewCtx.clearRect(0, 0, PREVIEW_W, PREVIEW_H);
		previewCtx.fillStyle = '#1c1c1c';
		previewCtx.fillRect(0, 0, PREVIEW_W, PREVIEW_H);
		previewCtx.drawImage(img, label.x, label.y, label.width, label.height, dx, dy, dw, dh);
	}

	function scheduleNext() {
		if (!isPlaying || timeline.length === 0) return;
		playTimer = window.setTimeout(() => {
			if (!isPlaying) return;
			currentFrame = (currentFrame + 1) % timeline.length;
			drawPreview();
			scheduleNext();
		}, timeline[currentFrame].duration);
	}

	function togglePlay() {
		if (isPlaying) {
			isPlaying = false;
			if (playTimer !== null) { clearTimeout(playTimer); playTimer = null; }
		} else {
			if (timeline.length === 0) return;
			isPlaying = true;
			scheduleNext();
		}
	}

	function addFrame() {
		if (labels.length === 0) return;
		timeline = [...timeline, { labelIndex: addLabelIndex, duration: 100 }];
		if (timeline.length === 1) { currentFrame = 0; drawPreview(); }
	}

	function removeFrame(idx: number) {
		if (timeline.length <= 1 && isPlaying) togglePlay();
		timeline = timeline.filter((_, i) => i !== idx);
		if (currentFrame >= timeline.length) currentFrame = Math.max(0, timeline.length - 1);
		if (timeline.length > 0) drawPreview();
	}

	function setFrameDuration(idx: number, val: string) {
		const d = parseInt(val);
		if (isNaN(d) || d < 1) return;
		const nl = [...timeline];
		nl[idx] = { ...nl[idx], duration: d };
		timeline = nl;
	}

	function setAllDurations() {
		const d = parseInt(bulkDuration);
		if (isNaN(d) || d < 1) return;
		timeline = timeline.map(f => ({ ...f, duration: d }));
		bulkDuration = '';
	}

	function handleDragStart(e: DragEvent, idx: number) {
		dragIndex = idx;
		if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
	}

	function handleDragOver(e: DragEvent, idx: number) {
		e.preventDefault();
		if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
		dropIndex = idx;
	}

	function handleDrop(e: DragEvent, idx: number) {
		e.preventDefault();
		if (dragIndex === null || dragIndex === idx) { dragIndex = null; dropIndex = null; return; }
		const nl = [...timeline];
		const [removed] = nl.splice(dragIndex, 1);
		nl.splice(idx, 0, removed);
		timeline = nl;
		dragIndex = null; dropIndex = null;
	}

	function handleDragEnd() { dragIndex = null; dropIndex = null; }

	function selectFrame(idx: number) {
		if (isPlaying) { isPlaying = false; if (playTimer !== null) { clearTimeout(playTimer); playTimer = null; } }
		currentFrame = idx;
		drawPreview();
	}

	$effect(() => {
		if (!previewCanvas) return;
		previewCtx = previewCanvas.getContext('2d');
	});

	$effect(() => {
		if (timeline.length > 0) drawPreview();
	});

	onMount(() => {
		if (labels.length > 0 && timeline.length === 0) addAllFrames();
	});

	function addAllFrames() {
		const existing = new Set(timeline.map(f => f.labelIndex));
		const newFrames = labels
			.map((_, i) => i)
			.filter(i => !existing.has(i))
			.map(i => ({ labelIndex: i, duration: 100 }));
		if (newFrames.length === 0) return;
		timeline = [...timeline, ...newFrames];
		if (timeline.length > 0 && currentFrame === 0) { drawPreview(); }
	}

	function deleteAllFrames() {
		if (isPlaying) togglePlay();
		timeline = [];
		currentFrame = 0;
	}
</script>

<div class="flex flex-col gap-4 h-full">
	{#if !hasImage}
		<div class="flex flex-col items-center justify-center h-full text-neutral-500 select-none py-16">
			<span class="material-icons text-5xl mb-2">movie</span>
			<p class="text-sm">Load a spritesheet in the Sprite Labeler tab first</p>
		</div>
	{:else}
		<div class="flex items-center gap-4">
			<div class="relative border border-neutral-700 rounded bg-neutral-950">
				<canvas bind:this={previewCanvas} width={PREVIEW_W} height={PREVIEW_H} class="block"></canvas>
				{#if timeline.length === 0}
					<div class="absolute inset-0 flex items-center justify-center text-neutral-600 text-sm bg-neutral-950/80">
						No frames — add sprites below
					</div>
				{/if}
			</div>
			<div class="flex flex-col gap-2">
				<button onclick={togglePlay} disabled={timeline.length === 0}
					class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed {isPlaying ? 'bg-red-700 hover:bg-red-600' : 'bg-green-700 hover:bg-green-600'}">
					<span class="material-icons text-sm">{isPlaying ? 'stop' : 'play_arrow'}</span>
					{isPlaying ? 'Stop' : 'Play'}
				</button>
				<span class="text-xs text-neutral-400">
					Frame {timeline.length > 0 ? currentFrame + 1 : 0} / {timeline.length}
				</span>
				<span class="text-xs text-neutral-600">
					{timeline.length > 0 ? timeline[currentFrame]?.duration ?? 100 : 0}ms
				</span>
			</div>
		</div>

		<div class="flex-1 flex flex-col min-h-0 gap-2">
			<div class="flex items-center gap-2 flex-wrap">
				<span class="text-xs text-neutral-400 font-semibold uppercase tracking-wider">Timeline</span>
				<span class="text-xs text-neutral-600">{timeline.length} frame{timeline.length !== 1 ? 's' : ''}</span>
				<div class="flex items-center gap-2 ml-4">
					<select bind:value={addLabelIndex} class="bg-neutral-800 border border-neutral-700 rounded text-xs px-2 py-1 outline-none">
						{#each labels as label, i}
							<option value={i}>{label.name}</option>
						{/each}
					</select>
					<button onclick={addFrame}
						class="flex items-center gap-1 px-2 py-1 bg-neutral-700 hover:bg-neutral-600 rounded text-xs cursor-pointer">
						<span class="material-icons text-xs">add</span> Add
					</button>
				</div>
				<div class="ml-auto flex items-center gap-2">
					<button onclick={addAllFrames} disabled={labels.length === 0}
						class="flex items-center gap-1 px-2 py-1 bg-neutral-700 hover:bg-neutral-600 rounded text-xs disabled:opacity-40 cursor-pointer">
						<span class="material-icons text-xs">select_all</span> Add all
					</button>
					<button onclick={deleteAllFrames} disabled={timeline.length === 0}
						class="flex items-center gap-1 px-2 py-1 bg-red-800 hover:bg-red-700 rounded text-xs disabled:opacity-40 cursor-pointer">
						<span class="material-icons text-xs">delete_sweep</span> Delete all
					</button>
					<input type="number" bind:value={bulkDuration} placeholder="ms"
						class="w-20 bg-neutral-800 border border-neutral-700 rounded text-xs px-2 py-1 outline-none" />
					<button onclick={setAllDurations} disabled={bulkDuration === '' || timeline.length === 0}
						class="px-2 py-1 bg-neutral-700 hover:bg-neutral-600 rounded text-xs disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
						Set all
					</button>
				</div>
			</div>

			<div class="flex-1 overflow-x-auto overflow-y-hidden min-h-0">
				{#if timeline.length === 0}
					<p class="text-xs text-neutral-600">Add sprites to build your animation timeline.</p>
				{:else}
					<div class="flex gap-2 items-start h-full pb-2">
						{#each timeline as entry, i (entry)}
							{@const label = labels[entry.labelIndex]}
							{@const s = img ? Math.min(64 / label.width, 80 / label.height) : 1}
							<div
								class="flex flex-col items-center gap-1.5 w-24 shrink-0 p-2 rounded text-xs cursor-pointer
									{currentFrame === i ? 'bg-neutral-700 ring-2 ring-green-500' : 'bg-neutral-800 hover:bg-neutral-750'}
									{dropIndex === i ? 'ring-2 ring-blue-500' : ''}"
								draggable="true"
								ondragstart={(e) => handleDragStart(e, i)}
								ondragover={(e) => handleDragOver(e, i)}
								ondrop={(e) => handleDrop(e, i)}
								ondragend={handleDragEnd}
								onclick={() => selectFrame(i)}
								role="button" tabindex="0"
								onkeydown={(e) => e.key === 'Enter' && selectFrame(i)}
							>
								<span class="material-icons text-xs text-neutral-600">drag_indicator</span>
								<div
									class="w-16 h-20 shrink-0 bg-neutral-950 rounded border border-neutral-600 flex items-center justify-center overflow-hidden"
								>
									<div
										style="width:{label.width * s}px;height:{label.height * s}px;background-image:url({img?.src});background-repeat:no-repeat;background-position:{(-label.x * s).toFixed(0)}px {(-label.y * s).toFixed(0)}px;background-size:{(img?.naturalWidth ?? 1) * s}px {(img?.naturalHeight ?? 1) * s}px;"
									></div>
								</div>
								<span class="text-neutral-400 w-full text-center truncate leading-tight">{label.name}</span>
								<div class="flex items-center gap-1">
									<input type="number" value={entry.duration}
										oninput={(e) => setFrameDuration(i, (e.target as HTMLInputElement).value)}
										class="w-14 bg-neutral-900 border border-neutral-700 rounded px-1 py-0.5 text-[10px] outline-none text-center"
										min="1" />
									<button onclick={() => removeFrame(i)}
										class="text-neutral-600 hover:text-red-400 cursor-pointer" title="Delete">
										<span class="material-icons text-xs">close</span>
									</button>
								</div>
							</div>
						{/each}
					</div>
				{/if}
			</div>
		</div>
	{/if}
</div>