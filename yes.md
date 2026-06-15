# Komputer Grafik — Persiapan Ujian (Bagian Arkan)
### Game: Bababooeys Can (Not) Move | Role: Monster AI, Lighting, Assets
### bpy Scripts: `lantern.py` · `lever_box.py` · `coal_generator.py`

---

## DAFTAR ISI
1. [Transformasi 3D](#1-transformasi-3d)
2. [Pembuatan Asset 3D — Script Asli](#2-pembuatan-asset-3d--script-asli)
3. [UV Mapping](#3-uv-mapping)
4. [Texturing & Material PBR](#4-texturing--material-pbr)
5. [Lighting](#5-lighting)
6. [Konsep Rendering Relevan](#6-konsep-rendering-relevan)
7. [Ringkasan Cepat Ujian](#7-ringkasan-cepat-ujian)

---

## 1. TRANSFORMASI 3D

### 1.1 Teori Dasar

Transformasi 3D adalah operasi matematis yang mengubah posisi, orientasi, atau ukuran objek di ruang 3D. Ada tiga transformasi fundamental yang direpresentasikan sebagai **matriks 4×4** dengan **koordinat homogen**:

```
Translasi          Rotasi (sumbu Y, sudut θ)    Skala
[1  0  0  tx]      [ cosθ  0  sinθ  0]          [sx  0   0   0]
[0  1  0  ty]      [  0    1    0   0]          [ 0  sy  0   0]
[0  0  1  tz]      [-sinθ  0  cosθ  0]          [ 0   0  sz  0]
[0  0  0   1]      [  0    0    0   1]          [ 0   0   0  1]
```

**Urutan TRS**: `M_final = T × R × S`
Titik yang ditransformasi: `P' = M_final × P`

> Perkalian matriks **tidak komutatif**: `T × R ≠ R × T`

---

### 1.2 Transformasi di lantern.py — Frustum Box (Tapered)

Fungsi `make_tapered_box()` di `lantern.py` membangun **frustrumrectangular** (prisma terpancung) secara **manual vertex-per-vertex** — bukan menggunakan primitive standar Blender. Ini adalah contoh **transformasi geometri langsung** (direct vertex placement):

```python
def make_tapered_box(name, bot_hx, bot_hy, top_hx, top_hy, z_bot, z_top, cx=0, cy=0):
    v = [
        # Bottom corners — half-extents: bot_hx, bot_hy
        (cx - bot_hx, cy - bot_hy, z_bot),  # 0: front-left  bottom
        (cx + bot_hx, cy - bot_hy, z_bot),  # 1: front-right bottom
        (cx + bot_hx, cy + bot_hy, z_bot),  # 2: back-right  bottom
        (cx - bot_hx, cy + bot_hy, z_bot),  # 3: back-left   bottom
        # Top corners — half-extents: top_hx, top_hy  (BERBEDA dari bottom)
        (cx - top_hx, cy - top_hy, z_top),  # 4: front-left  top
        (cx + top_hx, cy - top_hy, z_top),  # 5: front-right top
        (cx + top_hx, cy + top_hy, z_top),  # 6: back-right  top
        (cx - top_hx, cy + top_hy, z_top),  # 7: back-left   top
    ]
```

**Kenapa frustum, bukan kubus biasa?**
Pillar lantern memiliki `PIL_BOT_C = 0.215` (center offset bawah) dan `PIL_TOP_C = 0.255` (center offset atas). Artinya pillar *condong ke luar* saat naik → menciptakan taper khas lentera pagoda. Ini **tidak bisa** dibuat dengan `primitive_cube_add` + scale saja.

**Kelas geometri**: Frustum rectangular = *truncated right rectangular prism* = transformasi scale yang berbeda per Z.

---

### 1.3 Transformasi di lantern.py — Rotasi Torus Handle

```python
def create_ring():
    bpy.ops.mesh.primitive_torus_add(
        major_radius = RING_MAJOR_R,   # 0.110 m — radius lingkaran besar
        minor_radius = RING_MINOR_R,   # 0.042 m — radius tabung
        major_segments = 12,
        minor_segments = 8,
        location = (0.0, 0.0, RING_Z), # TRANSLASI: posisi Z = 1.000 m
        rotation = (math.pi / 2, 0.0, 0.0),  # ROTASI 90° sumbu X
    )
```

**Kenapa rotasi 90°?**
Default torus di Blender berbaring horizontal (ring di bidang XY). Memutar 90° terhadap sumbu X membuatnya **berdiri tegak** (ring di bidang XZ) → terlihat seperti cincin pegangan.

Dalam matriks rotasi sumbu X (θ = π/2):
```
Rx(90°) = [1   0      0    0]
          [0  cos90  -sin90  0]   =   [1  0   0  0]
          [0  sin90   cos90  0]       [0  0  -1  0]
          [0   0      0    1]         [0  1   0  0]
                                       [0  0   0  1]
```
Y → Z, Z → -Y: ring yang tadinya di XY sekarang di XZ.

---

### 1.4 Transformasi di lever_box.py — Konstruksi Arc Parametrik

Fungsi `build_housing()` membangun **semi-silinder** (busur setengah lingkaran) menggunakan matematika trigonometri secara eksplisit. Ini bukan primitive — tiap vertex dihitung dari persamaan lingkaran:

```python
def build_housing():
    R = HOUSING_RADIUS  # 0.080 m
    N = HOUSING_SEGS    # 8 segmen
    half_len = HOUSING_LEN / 2  # 0.10 m

    for i in range(N + 1):          # 0, 1, 2, ..., 8  →  9 titik arc
        t = math.pi * i / N         # t ∈ [0, π]  (setengah lingkaran)
        y = -R * math.cos(t)        # Y: −R → 0 → +R  (kiri ke kanan)
        z_local = R * math.sin(t)   # Z:  0 → R → 0   (naik lalu turun)

        vf = bm.verts.new((-half_len, y, z_base + z_local))  # front
        vb = bm.verts.new(( half_len, y, z_base + z_local))  # back
```

**Matematika**: Persamaan lingkaran parametrik `(y, z) = (R·cos θ, R·sin θ)` untuk `θ ∈ [0, π]` menghasilkan setengah lingkaran dari kiri ke kanan melewati puncak. Inilah busur housing.

---

### 1.5 Transformasi Pivot — lever_box.py (KRITIS untuk Animasi)

Ini adalah konsep transformasi yang paling penting di lever_box.py:

```python
PIVOT_Z = PLATE_H  # 0.040 m = titik engsel lever

# Setelah join shaft + knob:
def set_origin_to_world(obj, x, y, z):
    bpy.context.scene.cursor.location = (x, y, z)      # pindah cursor ke (0,0,0.04)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")    # pindah origin ke cursor
    # → semua vertex SHIFT secara lokal, tapi posisi DUNIA tetap
```

**Efeknya dalam local space `Lever_Handle`:**

| Local Z | World Z | Bagian |
|---------|---------|--------|
| 0.000   | 0.040   | Pivot / engsel housing |
| 0.260   | 0.300   | Tengah shaft |
| 0.520   | 0.560   | Pusat knob |

**Di Roblox**, animasi lever menjadi trivial karena pivot sudah tepat:
```lua
local h = model:FindFirstChild("Lever_Handle")
h.CFrame = h.CFrame * CFrame.fromAxisAngle(Vector3.xAxis, math.rad(angle))
-- Rotasi terjadi tepat di engsel housing, bukan di tengah objek
```

---

### 1.6 Transformasi di coal_generator.py — Non-Uniform Scale

```python
SCALE_X_RANGE = (0.80, 1.40)
SCALE_Y_RANGE = (0.70, 1.30)
SCALE_Z_RANGE = (0.50, 0.88)   # Z lebih pendek → batu terasa "berat ke bawah"

# Tiap chunk punya seed sendiri → scale berbeda-beda
scale_x = random.uniform(*SCALE_X_RANGE)
scale_y = random.uniform(*SCALE_Y_RANGE)
scale_z = random.uniform(*SCALE_Z_RANGE)

obj.scale = (scale_x, scale_y, scale_z)
bpy.ops.object.transform_apply(scale=True)  # bake scale ke vertex data
```

**Kenapa `transform_apply`?** Kalau scale tidak di-apply, FBX yang di-export akan membawa scale yang "tertunda" di metadata. Roblox membaca vertex data, bukan pending transform — jadi scale harus di-bake ke posisi vertex terlebih dahulu.

**Matriks skala** yang diapply:
```
S = [scale_x    0        0      0]
    [   0     scale_y    0      0]
    [   0        0    scale_z  0]
    [   0        0        0     1]
```
Setiap vertex `(x, y, z)` dikali S → `(x·sx, y·sy, z·sz)`.

---

### 1.7 Hierarki Transformasi Parent-Child (lantern.py)

```python
def build_lantern():
    base    = create_base()           # ROOT parent
    pil_fl  = create_pillar(-1, -1)   # children
    pil_fr  = create_pillar( 1, -1)
    glass   = create_glass()
    roof    = create_roof()
    collar  = create_top_collar()
    ring    = create_ring()

    children = (pil_fl, pil_fr, pil_bl, pil_br, glass, roof, collar, ring)
    for child in children:
        child.parent = base            # parent-child relationship
```

**Efek**: Saat `Lantern_Base` di-transform (pindah, putar, scale), semua children ikut secara otomatis — *tanpa* perlu transform tiap-tiap anak secara manual. Ini adalah **hierarchical transformation**.

Di Roblox, hierarki ini dipertahankan dalam struktur `Model > Parts`:
```
LanternModel (Model)
├── Lantern_Base      ← PrimaryPart
├── Lantern_Glass     ← Material transparency
├── Lantern_Roof
├── Lantern_Pillar_FL  ... (dst.)
└── Lantern_Ring
```

---

### 1.8 Transformasi di Roblox — MonsterAI

```lua
-- Konversi grid → world (operasi SCALE)
local function gridToWorld(col, row)
    return Vector3.new(col * Constants.TILE_SIZE, 0, row * Constants.TILE_SIZE)
end
-- tile(2,3) → world(16, 0, 24) : skala 8 stud per tile

-- Monster menghadap player (LookAt = rotasi)
monster.PrimaryPart.CFrame = CFrame.lookAt(monsterPos, playerPos)

-- Gerakan smooth (interpolasi / Lerp antara dua CFrame)
monster.PrimaryPart.CFrame = current:Lerp(target, dt * 5)
-- Lerp: P(t) = P0 + t(P1 - P0), 0 ≤ t ≤ 1
```

---

## 2. PEMBUATAN ASSET 3D — SCRIPT ASLI

### 2.1 lantern.py — Pagoda Lantern

**Komponen dan teknik yang dipakai:**

| Komponen | Fungsi bpy | Teknik CG |
|----------|-----------|-----------|
| `Lantern_Base` | `make_tapered_box()` | Frustum rectangular, manual vertex |
| `Lantern_Pillar_FL/FR/BL/BR` | `make_tapered_box()` | Frustum dengan offset XY per kolom |
| `Lantern_Glass` | `make_tapered_box()` | Objek TERPISAH untuk material transparency |
| `Lantern_Roof` | `build_mesh_object()` dengan 3 vertex ring | Custom mesh 12 vert, 10 face |
| `Lantern_Top_Collar` | `make_tapered_box()` | Frustum (non-tapered = box) |
| `Lantern_Ring` | `primitive_torus_add()` | Torus + rotasi 90° |

**Roof — tiga ring vertex:**

```python
v = [
    # Ring 0 — eave (paling lebar, sedikit di bawah frame top → efek droop pagoda)
    (-er, -er, ez), (er, -er, ez), (er, er, ez), (-er, er, ez),  # 0-3
    # Ring 1 — mid slope
    (-mr, -mr, mz), (mr, -mr, mz), (mr, mr, mz), (-mr, mr, mz), # 4-7
    # Ring 2 — peak (paling sempit, paling atas)
    (-pr, -pr, pz), (pr, -pr, pz), (pr, pr, pz), (-pr, pr, pz), # 8-11
]
f = [
    (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7),  # 4 eave slope (ring0→ring1)
    (4,5,9,8), (5,6,10,9), (6,7,11,10), (7,4,8,11),  # 4 body slope (ring1→ring2)
    (8,9,10,11),  # top cap
    (3,2,1,0),    # bottom cap (nutup manifold)
]
```

**Konsep CG**: Atap pagoda dibuat dari **vertex rings** yang mengecil ke atas. Ini adalah teknik modeling dasar untuk kubah, kerucut, dan atap bertingkat.

**`Lantern_Glass` — terpisah untuk material:**
Script secara eksplisit membuat glass sebagai objek sendiri (bukan gabung dengan pillar):
> *"Named 'Lantern_Glass' so it can be targeted independently in Roblox Studio to receive a transparency or neon material"*

Di Roblox Studio:
```
Lantern_Glass → SurfaceAppearance dengan Transparency tinggi
             → PointLight di dalamnya (Brightness=5, Range=16)
```

---

### 2.2 lever_box.py — Industrial Lever

**Komponen:**

```
Lever_Base (static)
  ├── Base plate   → primitive_cube_add + scale → transform_apply
  ├── 4 hex bolts  → primitive_cylinder_add(vertices=6, ...)
  └── Housing arch → bmesh arc parametrik (trigonometri)

Lever_Handle (animatable — pivot di PIVOT_Z = 0.04 m)
  ├── Shaft        → primitive_cylinder_add(vertices=12, ...)
  └── Knob         → primitive_uv_sphere_add(segments=16, ring_count=8, ...)
```

**Hexagonal bolt** (6-sisi):
```python
bpy.ops.mesh.primitive_cylinder_add(
    vertices = 6,           # ← hexagon! bukan circle
    radius   = BOLT_RADIUS,
    depth    = BOLT_HEIGHT,
    location = (x, y, z_centre),
)
```
`vertices=6` pada cylinder menghasilkan penampang **segi-6** (hexagon) = baut hex.

**join_into()** — penggabungan mesh:
```python
lever_base = join_into(
    components = [base_plate, bolt_fl, bolt_fr, bolt_bl, bolt_br, housing],
    active_component = base_plate,
    final_name = "Lever_Base",
)
```
Setelah join, semua komponen menjadi **satu mesh tunggal** → di Roblox jadi satu `MeshPart`, bukan kumpulan Part terpisah.

---

### 2.3 coal_generator.py — 5 Procedural Coal Chunks

**Algoritma per chunk:**
1. Set seed unik → `random.seed(seed)` → reproducible
2. Sample skala (sx, sy, sz) dari seed tersebut
3. Buat kubus base 0.30 m
4. Subdivide edges (cuts=1) → 26 vertex, 24 quad face
5. Bimodal vertex displacement
6. Recalculate normals
7. Apply scale
8. Set origin ke centroid geometri

**Bimodal displacement — inti algoritma:**
```python
SHARP_PROB = 0.35  # 35% vertex → protrusion tajam

def displace_vertex(co):
    if random.random() < SHARP_PROB:
        magnitude = random.uniform(0.04, 0.09)   # tier A: besar → tonjolan tajam
    else:
        magnitude = random.uniform(0.00, 0.022)  # tier B: kecil → facet datar

    co.x += random.uniform(-magnitude, magnitude)
    co.y += random.uniform(-magnitude, magnitude)
    co.z += random.uniform(-magnitude, magnitude)
```

**Kenapa bimodal?** Kalau semua vertex digerakkan seragam, batu terlihat smooth dan plastik. Dengan dua tier:
- 35% vertex gerak jauh → membentuk sudut tajam / tonjolan
- 65% vertex hampir diam → facet datar tercipta antara tonjolan

Hasilnya adalah batu batu yang terlihat **low-poly dan natural** sekaligus.

**bmesh subdivide:**
```python
bmesh.ops.subdivide_edges(bm, edges=pre_subdiv_edges, cuts=1, use_grid_fill=True)
# Kubus awal: 8 vert, 6 face
# Setelah subdivide: 26 vert (8 corner + 12 edge midpoint + 6 face center), 24 face
```

**5 chunk berbeda:**
```python
CHUNK_SEEDS = [17, 83, 251, 512, 999]
for i, seed in enumerate(CHUNK_SEEDS, start=1):
    chunk = generate_chunk(i, seed)
    export_chunk(chunk, i)
# Output: coal_1.fbx, coal_2.fbx, coal_3.fbx, coal_4.fbx, coal_5.fbx
```
5 file FBX berbeda → di Roblox bisa scatter random chunks untuk variasi visual.

---

## 3. UV MAPPING

### 3.1 Teori UV

UV coordinate memetakan setiap vertex mesh 3D ke posisi `(u, v)` pada texture 2D:
- **U** = horizontal, 0 (kiri) → 1 (kanan)
- **V** = vertikal, 0 (bawah) → 1 (atas)
- Proses "membuka" mesh 3D ke 2D = **UV Unwrapping**

### 3.2 UV di Script Arkan

Ketiga script Arkan tidak melakukan UV unwrap secara eksplisit di kode (focus pada geometry). UV akan dilakukan **manual di Blender** setelah import, atau menggunakan Smart UV Project sebelum export:

```python
# Ditambahkan sebelum export (untuk setiap asset):
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')

# Lantern & Lever: Smart UV Project (otomatis, cocok untuk low-poly)
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)

# Coal: Cube Projection (natural untuk batu)
bpy.ops.uv.cube_project(scale_to_bounds=True)

bpy.ops.object.mode_set(mode='OBJECT')
```

**Untuk Lantern_Glass** — perlu UV yang bersih karena akan diberi material transparency. Cylinder projection ideal:
```python
bpy.ops.uv.cylinder_project()
```

---

## 4. TEXTURING & MATERIAL PBR

### 4.1 Apa itu PBR

PBR (Physically Based Rendering) menggunakan model fisika untuk cahaya-material. Prinsip utama:
- **Energy Conservation**: tidak bisa pantulkan lebih dari yang diterima
- **Microfacet Theory**: roughness = ukuran tonjolan mikroskopik permukaan
- **Fresnel Effect**: refleksi lebih kuat dari sudut rendah

### 4.2 Channel Texture

| Channel | Deskripsi | Format |
|---------|-----------|--------|
| **Albedo** | Warna dasar, tanpa bayangan/highlight | RGB |
| **Normal Map** | Arah normal surface: R=X, G=Y, B=Z | RGB (biru dominan) |
| **Roughness** | 0=mirror halus, 1=matte kasar | Grayscale |
| **Metalness** | 0=non-metal (kayu/batu), 1=logam | Grayscale |
| **Emissive** | Bersinar sendiri tanpa cahaya eksternal | RGB |

**Normal map biru** = normal menghadap lurus keluar = surface flat.
Makin banyak R/G = normal miring = ada detail relief.

### 4.3 Texturing Per Asset Arkan

#### Lantern

| Bagian | Albedo | Roughness | Metalness | Special |
|--------|--------|-----------|-----------|---------|
| Base + Collar | Besi tua, kehitaman `#2a2a2a` | 0.75 (kasar) | 0.7 (metal berkarat) | Rust overlay di normal |
| 4 Pillar | Kayu gelap `#3d2b1f` | 0.85 | 0 | Wood grain normal |
| Glass | Kuning-oranye `#ffaa44` | 0.05 | 0 | **Transparency** 0.4, Neon material |
| Roof | Hitam-hijau `#1a2a1a` (patina) | 0.8 | 0.5 | Old lacquered metal |
| Ring | Abu logam `#5a5a5a` | 0.6 | 0.9 | Metal handle, wear marks |

**Lantern_Glass** di Roblox → gunakan `Neon` material atau `SurfaceAppearance` dengan warna emissive dan transparency. Cahaya api di dalamnya akan "tembus" visual keluar.

#### Lever Box

| Bagian | Albedo | Roughness | Metalness | Special |
|--------|--------|-----------|-----------|---------|
| Base plate | Abu gelap berkarat `#4a4040` | 0.85 | 0.4 | Rust patches di normal |
| Hex bolts | Abu lebih gelap | 0.7 | 0.8 | Hex bolt wear |
| Housing arch | Sama dengan base | 0.85 | 0.4 | Idem |
| Shaft | Hitam industrial `#222` | 0.6 | 0.6 | Grip tape texture |
| Knob | Merah tua `#8b0000` | 0.5 | 0.1 | Rubber/bakelite material |

#### Coal

| Channel | Deskripsi |
|---------|-----------|
| Albedo | Hitam sangat gelap `#0a0a0a` dengan sedikit variasi abu |
| Normal | Crack dan facet — cocok dengan geometry bimodal |
| Roughness | 0.95 (sangat matte, batu tidak mengkilap) |
| Metalness | 0 |
| Emissive | Slight orange glow di crevice (jika dekat fireplace) |

### 4.4 Implementasi Roblox (SurfaceAppearance)

```lua
-- Contoh untuk Lantern Glass
local glass = lanternModel:FindFirstChild("Lantern_Glass")
glass.Material = Enum.Material.Neon          -- bersinar dari dalam
glass.Color    = Color3.fromRGB(255, 160, 50) -- warm orange

-- Atau pakai SurfaceAppearance untuk PBR
local sa = Instance.new("SurfaceAppearance")
sa.ColorMap      = "rbxassetid://GLASS_ALBEDO"
sa.RoughnessMap  = "rbxassetid://GLASS_ROUGH"
sa.Parent        = glass

-- PointLight di dalam glass chamber
local light = Instance.new("PointLight")
light.Brightness = 5
light.Range      = 16
light.Color      = Color3.fromRGB(255, 140, 40)
light.Parent     = glass
```

---

## 5. LIGHTING

### 5.1 Model Pencahayaan — Referensi Teori

**Model Phong** (teori klasik):
```
I = Ka·Ia + Kd·Id·max(0, N·L) + Ks·Is·(R·V)^n

Ka/d/s = koefisien material (ambient/diffuse/specular)
Ia/d/s = intensitas cahaya
N = normal surface, L = arah ke cahaya
R = vektor refleksi, V = arah ke viewer
n = shininess
```

**PBR (dipakai Roblox)** — lebih akurat:
- Roughness menggantikan `n` (shininess)
- Metalness menggantikan `Ks`
- Energy conservation terjaga
- Menggunakan Cook-Torrance BRDF

### 5.2 Lantern PointLight

**Penempatan unik lantern**: PointLight diletakkan **di dalam** `Lantern_Glass`, bukan di luar. Cahaya menembus glass dan menyinari sekitar:

```lua
-- PointLight di dalam Lantern_Glass
local light = Instance.new("PointLight")
light.Brightness = 5      -- lebih terang dari torch biasa (cahaya dalam kotak)
light.Range      = 16     -- studs (sesuai rekomendasi di lantern.py docstring)
light.Color      = Color3.fromRGB(255, 140, 40)  -- warm amber
light.Shadows    = true   -- cast shadows dari frame pillar
light.Parent     = lanternModel:FindFirstChild("Lantern_Glass")
```

**Atenuasi cahaya (light attenuation)**:
```
I(d) ≈ Brightness × (1 - d/Range)²

d = 0        → I = 5.0   (penuh di dalam glass)
d = 8  studs → I = 1.25  (setengah radius)
d = 16 studs → I = 0     (batas jangkauan)
```

**Kenapa PointLight di dalam glass?** Cahaya api di dunia nyata berasal dari **dalam** badan lentera, tidak dari luar. Menempatkan PointLight di dalam Lantern_Glass mereplikasi perilaku ini: cahaya "bocor" dari dalam ke luar, dan frame pillar akan **cast shadow** di sekitarnya → efek atmospheric lebih kuat.

### 5.3 Lantern Flicker (Animasi Prosedural)

```lua
local RunService = game:GetService("RunService")
local glass = lanternModel:FindFirstChild("Lantern_Glass")
local light = glass:FindFirstChildOfClass("PointLight")

local BASE = 5.0    -- brightness base (lebih terang karena Brightness=5)
local A1   = 0.4    -- amplitudo gelombang 1 (api besar)
local F1   = 6      -- frekuensi gelombang 1 (Hz)
local A2   = 0.15   -- amplitudo gelombang 2 (flicker kecil)
local F2   = 19     -- frekuensi gelombang 2 (Hz)

RunService.Heartbeat:Connect(function()
    local t = tick()
    -- Dua gelombang sinus: F1 dan F2 harus bukan kelipatan satu sama lain
    -- → pola tidak berulang → terasa seperti api nyata
    light.Brightness = BASE
        + math.sin(t * F1) * A1
        + math.sin(t * F2) * A2
end)
```

**Mengapa dua gelombang?** Fungsi `sin(t)` tunggal sangat regular/monoton. Menjumlahkan dua sin dengan frekuensi berbeda (*beating*) menghasilkan interferensi yang tampak alami. F1=6 dan F19=19 (tidak ada faktor persekutuan besar) → pola tidak berulang dalam waktu lama.

### 5.4 Ambient Darkness System

```lua
local Lighting = game:GetService("Lighting")

-- Setup awal: sangat gelap
Lighting.Ambient        = Color3.fromRGB(20, 20, 25)  -- biru gelap
Lighting.Brightness     = 0.8
Lighting.GlobalShadows  = true
```

**Monster proximity darkening:**
```lua
local function updateDarkness(monster, player)
    local dist = (monster.PrimaryPart.Position - player.Character.PrimaryPart.Position).Magnitude
    local MAX, MIN = 40, 8
    local t = math.clamp((MAX - dist) / (MAX - MIN), 0, 1)

    -- Lerp warna: C(t) = C_start + t × (C_end - C_start) per channel
    Lighting.Ambient = Color3.fromRGB(20, 20, 25):Lerp(Color3.fromRGB(5, 5, 8), t)
end
```

### 5.5 Emissive vs PointLight

| | Emissive Material | PointLight |
|--|---|---|
| Fungsi | Objek *terlihat* menyala | Objek *menerangi* area sekitar |
| Contoh | Lantern_Glass (glow visual), eye monster | Lantern cahaya ke environment |
| Biaya GPU | Rendah | Lebih tinggi (apalagi dengan Shadows) |
| Menerangi objek lain? | **Tidak** | **Ya** |

**Keduanya dipakai bersama** pada Lantern_Glass: Neon/emissive material agar glass *terlihat* menyala, PointLight agar *menerangi sekitar*.

---

## 6. KONSEP RENDERING RELEVAN

### 6.1 Raycasting — Vision Monster

```lua
-- Cek apakah player dalam cone pandangan (dot product)
local function isInVisionCone(monster, player)
    local forward   = monster.PrimaryPart.CFrame.LookVector  -- unit vector
    local toPlayer  = (player.Character.PrimaryPart.Position
                      - monster.PrimaryPart.Position).Unit

    -- A · B = cos(θ) ketika A dan B adalah unit vector
    local cosAngle = forward:Dot(toPlayer)
    local angle    = math.acos(math.clamp(cosAngle, -1, 1))  -- radian

    return angle < math.rad(Constants.MONSTER_VISION_ANGLE)  -- 60 derajat
end

-- Cek line of sight (ada penghalang?)
local function hasLineOfSight(monster, player)
    local origin    = monster.PrimaryPart.Position + Vector3.new(0, 1.5, 0)
    local direction = (player.Character.PrimaryPart.Position - origin)
    local params    = RaycastParams.new()
    params.FilterDescendantsInstances = {monster}
    local result = workspace:Raycast(origin, direction, params)
    return result and result.Instance:IsDescendantOf(player.Character)
end
```

**Matematika**: `cos(θ) = A·B` untuk unit vector. Jika `θ < 60°` → dalam cone.

### 6.2 Bounding Sphere — Catch Radius & MONSTER_REACH Rule

```lua
local function checkCatch(monster, player, activeRules)
    local radius = Constants.MONSTER_REACH_BASE  -- 4 studs default

    if table.find(activeRules, Constants.Rules.MONSTER_REACH) then
        radius = radius + Constants.MONSTER_REACH_BONUS  -- +10 studs → total 14
    end

    local distance = (monster.PrimaryPart.Position
                    - player.Character.PrimaryPart.Position).Magnitude

    return distance <= radius  -- bounding sphere intersection test
end
```

**Sphere intersection**: dua sphere (monster radius + player radius≈0) berpotongan jika `distance(A,B) ≤ rA + rB`.

### 6.3 Face Normal Recalculation

Ketiga script menggunakan `bmesh.ops.recalc_face_normals()`. Normal adalah vektor tegak lurus permukaan yang menentukan arah pencahayaan:

```python
# Setelah geometry selesai:
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
bm.normal_update()
```

**Kenapa penting?** Normal yang salah arah menyebabkan permukaan terlihat hitam (cahaya dihitung dari sisi yang salah). `recalc_face_normals` memastikan semua normal mengarah **keluar** dari mesh (outward-facing).

**Syarat**: Mesh harus **manifold** (setiap edge shared oleh tepat 2 face). Itulah kenapa `lantern.py` menambahkan "bottom cap" di roof meski tidak terlihat — untuk menutup mesh menjadi solid tertutup.

### 6.4 Koordinat: Blender vs Roblox

```
Blender (Z-up)    →    Roblox (Y-up)
   Z  (atas)      →    Y  (atas)
   Y  (belakang)  →    -Z (belakang)
   X  (kanan)     →    X  (kanan)
```

Semua script menggunakan:
```python
bpy.ops.export_scene.fbx(
    axis_forward = "-Z",   # Blender -Z → Roblox forward
    axis_up      = "Y",    # Blender Y → Roblox up
    bake_space_transform = True,  # bake rotasi sumbu ke dalam vertex data
)
```

---

## 7. RINGKASAN CEPAT UJIAN

### Konsep yang HARUS Bisa Dijelaskan Arkan:

**Transformasi 3D:**
- Tiga transformasi: translasi, rotasi, skala → matriks 4×4
- Urutan TRS penting karena matriks tidak komutatif
- `make_tapered_box()` = frustum rectangular = vertex placement manual
- Torus rotasi 90°: mengubah ring horizontal → berdiri tegak
- Arc parametrik (lever housing): `y = R·cos(t)`, `z = R·sin(t)`, `t ∈ [0, π]`
- Pivot placement (`set_origin_to_world`) = critical untuk animasi lever di Roblox

**Texturing PBR:**
- Albedo = warna dasar (no lighting baked)
- Normal map = encoding arah normal di RGB: biru dominan = permukaan datar
- Roughness = 0 (mirror) → 1 (matte)
- Metalness = 0 (kayu/batu) → 1 (logam)
- Emissive = bersinar sendiri, tidak butuh cahaya luar
- Lantern_Glass: emissive/neon + PointLight di dalam chamber

**Lighting:**
- PointLight: Brightness, Range, Color, Shadows
- Atenuasi: `I(d) ≈ Brightness × (1 - d/Range)²`
- Flicker: dua gelombang sin berbeda frekuensi → pola organik
- Ambient darkness: global `Lighting.Ambient` sangat gelap → horror atmosphere
- Monster proximity: lerp ambient ke lebih gelap saat monster dekat

**Rendering:**
- Raycast: ray dari monster → cek apakah ada penghalang → vision system
- Dot product: `cos(θ) = A·B` → cone check vision
- Bounding sphere: `distance ≤ radius` → catch check + MONSTER_REACH rule
- Face normals: outward-facing untuk lighting benar, butuh manifold mesh

### Rumus Penting:

```
Dot product (angle check)  :  cos(θ) = A · B       (A, B unit vectors)
Lerp (interpolasi)         :  P(t) = P0 + t(P1-P0)   0 ≤ t ≤ 1
Grid → World               :  worldX = col × TILE_SIZE (= 8 studs)
Light attenuation          :  I(d) ≈ Brightness × (1 - d/Range)²
Bounding sphere catch      :  caught = dist(monster, player) ≤ catchRadius
Arc parametrik             :  y = R·cos(t),  z = R·sin(t),  t ∈ [0, π]
Non-uniform scale          :  v' = (x·sx, y·sy, z·sz)
```

### Kode Yang Harus Hafal:

```python
# Frustum box (manual vertex)
v = [(cx-bx, cy-by, z0), ..., (cx-tx, cy-ty, z1), ...]  # bottom then top

# Arc parametrik
t = math.pi * i / N
y = -R * math.cos(t)
z = R * math.sin(t)

# Bimodal displacement
if random.random() < 0.35:
    mag = random.uniform(0.04, 0.09)  # sharp
else:
    mag = random.uniform(0.00, 0.022) # flat
```

```lua
-- Flicker
light.Brightness = BASE + math.sin(tick()*F1)*A1 + math.sin(tick()*F2)*A2

-- Proximity darken
local t = math.clamp((MAX-dist)/(MAX-MIN), 0, 1)
Lighting.Ambient = normalAmb:Lerp(darkAmb, t)

-- Catch check + reach rule
if table.find(rules, "monster_reach") then radius += REACH_BONUS end
return (monster.Pos - player.Pos).Magnitude <= radius
```
