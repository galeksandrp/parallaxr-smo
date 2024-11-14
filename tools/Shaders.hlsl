//#define HEIGHTMAP_DOUBLEPRECISION
//#define WRAPPED_TEXTURE
//#define CLAMP_EDGES

struct Vertex2D
{
	float2 Position : POSITION;
	float2 TexCoord : TEXCOORD0;
	float4 Colour   : COLOR0;
};

struct DeltasOutput
{
	uint4 DeltasA : SV_Target0;
	uint4 DeltasB : SV_Target1;
	uint4 DeltasC : SV_Target2;
};

#ifdef WRAPPED_TEXTURE
SamplerState MaskTextureSampler
{
	Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
	AddressU = Wrap;
	AddressV = Wrap;
};
#else
SamplerState MaskTextureSampler
{
	Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
	AddressU = Clamp;
	AddressV = Clamp;
};
#endif

//--

float MaxStepHeight = 50;

static const int DirNorth = 0;
static const int DirNorthEast = 1;
static const int DirEast = 2;
static const int DirSouthEast = 3;
static const int DirSouth = 4;
static const int DirSouthWest = 5;
static const int DirWest = 6;
static const int DirNorthWest = 7;

static const float2 DirVec[8] =
{
	float2(0, -1),
	float2(-1, -1),
	float2(-1, 0),
	float2(-1, 1),
	float2(0, 1),
	float2(1, 1),
	float2(1, 0),
	float2(1, -1)
};

static const int2 SampleOffsets[20] =
{
	int2(-1, 0),
	int2(0, -1),
	int2(1, 0),
	int2(0, 1),
	int2(-1, -1),
	int2(1, 1),
	int2(-1, 1),
	int2(1, -1),
	int2(-2, 0),
	int2(0, -2),
	int2(2, 0),
	int2(0, 2),
	int2(-1, -2),
	int2(1, -2),
	int2(2, -1),
	int2(2, 1),
	int2(1, 2),
	int2(-1, 2),
	int2(-2, 1),
	int2(-2, -1)
};

#ifdef HEIGHTMAP_DOUBLEPRECISION
Texture2D<uint2> HeightMap  : register(t0);
#else
Texture2D<float> HeightMap  : register(t0);
#endif
Texture2D<uint4> DeltasA    : register(t1);
Texture2D<uint4> DeltasB    : register(t2);
Texture2D<uint4> DeltasC    : register(t3);
Texture2D<float4> NormalMap : register(t4);
Texture2D<float>  Mask      : register(t5);

SamplerState LinearSampler : register(s0);

struct VertexOutCol
{
	float4 Position : SV_POSITION;
	float4 Colour : COLOR0;
	float2 TexCoord : TEXCOORD0;
	float2 Argh : TEXCOORD1;
};

VertexOutCol Standard2D(const Vertex2D IN)
{
	VertexOutCol OUT;
	OUT.Position = float4(IN.Position, 0, 1);
	OUT.TexCoord = IN.TexCoord;
	OUT.Colour = IN.Colour;
	OUT.Argh = IN.Position;
	return OUT;
}

int3 GetWrappedCoord(int x, int y, uint width, uint height)
{
#ifdef WRAPPED_TEXTURE
	if (x < 0) x += width;
	if (x >= (int)width) x -= width;
	if (y < 0) y += height;
	if (y >= (int)height) y -= height;
#endif

	return float3(x, y, 0);
}

int3 GetWrappedCoord2(int2 pos, uint width, uint height)
{
	return GetWrappedCoord(pos.x, pos.y, width, height);
}

float3 GetNormal(int x, int y)
{
	uint Width;
	uint Height;
	uint Levels;
	NormalMap.GetDimensions(0, Width, Height, Levels);

	float3 Normal = NormalMap.Load(GetWrappedCoord(x, y, Width, Height)).xyz;
	Normal -= 0.5;
	Normal *= 2.0;

	return normalize(Normal);
}

float GetPixelDelta(int2 Position, float x, float y, int Dir)
{
	const float3 Normal = GetNormal(Position.x + x, Position.y + y);
	const float Dist = (Normal.x * DirVec[Dir].x) + (Normal.y * DirVec[Dir].y);
	const float XYLen = clamp(sqrt((Normal.y * Normal.y) + (Normal.x * Normal.x)), 0, 1);
	
	float Delta = 0.0;
	if (XYLen > 0)
	{
		Delta = clamp(tan(asin(XYLen)) * (Dist / XYLen), -MaxStepHeight, MaxStepHeight);
		if (Normal.z < 0)
			Delta = -Delta;
	}

	return Delta;
}

bool IsMasked(int2 Position, int2 Offset, float2 Dim)
{
	uint Width;
	uint Height;
	uint Levels;
	NormalMap.GetDimensions(0, Width, Height, Levels);

	float2 TexCoord = (Position + Offset) / Dim;
	return Mask.Sample(MaskTextureSampler, TexCoord) == 0;
}

DeltasOutput GenerateDeltas(const VertexOutCol IN)
{
	uint Width;
	uint Height;
	uint Levels;
	NormalMap.GetDimensions(0, Width, Height, Levels);

	float2 NMapSize = float2(Width, Height);

	int2 Pos = int2(IN.Position.xy);

	DeltasOutput OUTPUT;

	float Delta[20] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
	uint DeltaEnableFlags = 0;

	{
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[0], NMapSize))
			{
				Delta[0] = GetPixelDelta(Pos, -1, 0, DirEast);
					DeltaEnableFlags |= 1 << 0;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.y > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[1], NMapSize))
			{
				Delta[1] = GetPixelDelta(Pos, 0, -1, DirSouth);
				DeltaEnableFlags |= 1 << 1;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[2], NMapSize))
			{
				Delta[2] = GetPixelDelta(Pos, 0, 0, DirWest);
				DeltaEnableFlags |= 1 << 2;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.y < int(Height) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[3], NMapSize))
			{
				Delta[3] = GetPixelDelta(Pos, 0, 0, DirNorth);
				DeltaEnableFlags |= 1 << 3;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.x > 1 && Pos.y > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[4], NMapSize))
			{
				Delta[4] = GetPixelDelta(Pos, -1, -1, DirSouthEast);
				DeltaEnableFlags |= 1 << 4;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 1 && Pos.y < int(Height) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[5], NMapSize))
			{
				Delta[5] = GetPixelDelta(Pos, 0, 0, DirNorthWest);
				DeltaEnableFlags |= 1 << 5;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 1 && Pos.y < int(Height) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[6], NMapSize))
			{
				Delta[6] = GetPixelDelta(Pos, -1, 0, DirNorthEast);
				DeltaEnableFlags |= 1 << 6;
			}
		}

#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 1 && Pos.y > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[7], NMapSize))
			{
				Delta[7] = GetPixelDelta(Pos, 0, -1, DirSouthWest);
				DeltaEnableFlags |= 1 << 7;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[8], NMapSize))
			{
				Delta[8] = GetPixelDelta(Pos, -2, 0, DirEast);
				Delta[8] += GetPixelDelta(Pos, -1, 0, DirEast);
				DeltaEnableFlags |= 1 << 8;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.y > 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[9], NMapSize))
			{
				Delta[9] = GetPixelDelta(Pos, 0, -2, DirSouth);
				Delta[9] += GetPixelDelta(Pos, 0, -1, DirSouth);
				DeltaEnableFlags |= 1 << 9;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[10], NMapSize))
			{
				Delta[10] = GetPixelDelta(Pos, 1, 0, DirWest);
				Delta[10] += GetPixelDelta(Pos, 0, 0, DirWest);
				DeltaEnableFlags |= 1 << 10;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.y < int(Height) - 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[11], NMapSize))
			{
				Delta[11] = GetPixelDelta(Pos, 0, 1, DirNorth);
				Delta[11] += GetPixelDelta(Pos, 0, 0, DirNorth);
				DeltaEnableFlags |= 1 << 11;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 1 && Pos.y > 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[12], NMapSize))
			{
				Delta[12] = GetPixelDelta(Pos, -1, -2, DirSouthEast);
				Delta[12] += GetPixelDelta(Pos, 0, -1, DirSouth);
				Delta[12] += GetPixelDelta(Pos, -1, -2, DirSouth);
				Delta[12] += GetPixelDelta(Pos, -1, -1, DirSouthEast);
				Delta[12] *= 0.5f;
				DeltaEnableFlags |= 1 << 12;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 1 && Pos.y > 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[13], NMapSize))
			{
				Delta[13] = GetPixelDelta(Pos, 0, -2, DirSouthWest);
				Delta[13] += GetPixelDelta(Pos, 0, -1, DirSouth);
				Delta[13] += GetPixelDelta(Pos, 1, -2, DirSouth);
				Delta[13] += GetPixelDelta(Pos, 0, -1, DirSouthWest);
				Delta[13] *= 0.5f;
				DeltaEnableFlags |= 1 << 13;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 2 && Pos.y > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[14], NMapSize))
			{
				Delta[14] = GetPixelDelta(Pos, 1, -1, DirSouthWest);
				Delta[14] += GetPixelDelta(Pos, 0, 0, DirWest);
				Delta[14] += GetPixelDelta(Pos, 1, -1, DirWest);
				Delta[14] += GetPixelDelta(Pos, 0, -1, DirSouthWest);
				Delta[14] *= 0.5f;
				DeltaEnableFlags |= 1 << 14;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 2 && Pos.y < int(Height) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[15], NMapSize))
			{
				Delta[15] = GetPixelDelta(Pos, 1, 0, DirNorthWest);
				Delta[15] += GetPixelDelta(Pos, 0, 0, DirWest);
				Delta[15] += GetPixelDelta(Pos, 1, 1, DirWest);
				Delta[15] += GetPixelDelta(Pos, 0, 0, DirNorthWest);
				Delta[15] *= 0.5f;
				DeltaEnableFlags |= 1 << 15;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x < int(Width) - 1 && Pos.y < int(Height) - 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[16], NMapSize))
			{
				Delta[16] = GetPixelDelta(Pos, 0, 1, DirNorthWest);
				Delta[16] += GetPixelDelta(Pos, 0, 0, DirNorth);
				Delta[16] += GetPixelDelta(Pos, 1, 1, DirNorth);
				Delta[16] += GetPixelDelta(Pos, 0, 0, DirNorthWest);
				Delta[16] *= 0.5f;
				DeltaEnableFlags |= 1 << 16;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 1 && Pos.y < int(Height) - 2)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[17], NMapSize))
			{
				Delta[17] = GetPixelDelta(Pos, -1, 1, DirNorthEast);
				Delta[17] += GetPixelDelta(Pos, 0, 0, DirNorth);
				Delta[17] += GetPixelDelta(Pos, -1, 1, DirNorth);
				Delta[17] += GetPixelDelta(Pos, -1, 0, DirNorthEast);
				Delta[17] *= 0.5f;
				DeltaEnableFlags |= 1 << 17;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 2 && Pos.y < int(Height) - 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[18], NMapSize))
			{
				Delta[18] = GetPixelDelta(Pos, -2, 0, DirNorthEast);
				Delta[18] += GetPixelDelta(Pos, -1, 0, DirEast);
				Delta[18] += GetPixelDelta(Pos, -2, 1, DirEast);
				Delta[18] += GetPixelDelta(Pos, -1, 0, DirNorthEast);
				Delta[18] *= 0.5f;
				DeltaEnableFlags |= 1 << 18;
			}
		}
		
#ifndef WRAPPED_TEXTURE
		if (Pos.x > 2 && Pos.y > 1)
#endif
		{
			if (!IsMasked(Pos, SampleOffsets[19], NMapSize))
			{
				Delta[19] = GetPixelDelta(Pos, -2, -1, DirSouthEast);
				Delta[19] += GetPixelDelta(Pos, -1, 0, DirEast);
				Delta[19] += GetPixelDelta(Pos, -2, -1, DirEast);
				Delta[19] += GetPixelDelta(Pos, -1, -1, DirSouthEast);
				Delta[19] *= 0.5f;
				DeltaEnableFlags |= 1 << 19;
			}
		}
	}

	OUTPUT.DeltasA.x = f32tof16(Delta[0]);
	OUTPUT.DeltasA.x |= f32tof16(Delta[1]) << 16;
	OUTPUT.DeltasA.y = f32tof16(Delta[2]);
	OUTPUT.DeltasA.y |= f32tof16(Delta[3]) << 16;
	OUTPUT.DeltasA.z = f32tof16(Delta[4]);
	OUTPUT.DeltasA.z |= f32tof16(Delta[5]) << 16;
	OUTPUT.DeltasA.w = f32tof16(Delta[6]);
	OUTPUT.DeltasA.w |= f32tof16(Delta[7]) << 16;
	OUTPUT.DeltasB.x = f32tof16(Delta[8]);
	OUTPUT.DeltasB.x |= f32tof16(Delta[9]) << 16;
	OUTPUT.DeltasB.y = f32tof16(Delta[10]);
	OUTPUT.DeltasB.y |= f32tof16(Delta[11]) << 16;
	OUTPUT.DeltasB.z = f32tof16(Delta[12]);
	OUTPUT.DeltasB.z |= f32tof16(Delta[13]) << 16;
	OUTPUT.DeltasB.w = f32tof16(Delta[14]);
	OUTPUT.DeltasB.w |= f32tof16(Delta[15]) << 16;
	OUTPUT.DeltasC.x = f32tof16(Delta[16]);
	OUTPUT.DeltasC.x |= f32tof16(Delta[17]) << 16;
	OUTPUT.DeltasC.y = f32tof16(Delta[18]);
	OUTPUT.DeltasC.y |= f32tof16(Delta[19]) << 16;
	OUTPUT.DeltasC.z = DeltaEnableFlags;
	OUTPUT.DeltasC.w = 0;
	return OUTPUT;
}

#ifdef HEIGHTMAP_DOUBLEPRECISION
uint2 UpscaleHeight(const VertexOutCol IN) : SV_Target
{
	uint TexWidth;
	uint TexHeight;
	uint TexLevels;
	HeightMap.GetDimensions(0, TexWidth, TexHeight, TexLevels);

	int2 Position = int2(round(IN.TexCoord.x * TexWidth), round(IN.TexCoord.y * TexHeight));
	uint2 DoubleParts = HeightMap.Load(int3(Position, 0));
	double Height = asdouble(DoubleParts.x, DoubleParts.y) * 2.0;

	uint2 PackedHeight;
	asuint(Height, PackedHeight.x, PackedHeight.y);
	return PackedHeight;
}
#else
float UpscaleHeight(const VertexOutCol IN) : SV_Target
{
	return HeightMap.Sample(LinearSampler, IN.TexCoord).x * 2.0;
}
#endif

float4 GenNormalMip(const VertexOutCol IN) : SV_Target
{
	return NormalMap.Sample(LinearSampler, IN.TexCoord);
}

#ifdef HEIGHTMAP_DOUBLEPRECISION
uint2 UpdateHeights(const VertexOutCol IN) : SV_Target
#else
float UpdateHeights(const VertexOutCol IN) : SV_Target
#endif
{
	uint TextureWidth;
	uint TextureHeight;
	uint Levels;
	DeltasA.GetDimensions(0, TextureWidth, TextureHeight, Levels);

	double Deltas[20];

	uint4 Deltas8 = DeltasA.Load(int3(IN.Position.xy, 0));
	Deltas[0] = double(f16tof32(Deltas8.x & 0xFFFF));
	Deltas[1] = double(f16tof32(Deltas8.x >> 16));
	Deltas[2] = double(f16tof32(Deltas8.y & 0xFFFF));
	Deltas[3] = double(f16tof32(Deltas8.y >> 16));
	Deltas[4] = double(f16tof32(Deltas8.z & 0xFFFF));
	Deltas[5] = double(f16tof32(Deltas8.z >> 16));
	Deltas[6] = double(f16tof32(Deltas8.w & 0xFFFF));
	Deltas[7] = double(f16tof32(Deltas8.w >> 16));

	uint4 Deltas16 = DeltasB.Load(int3(IN.Position.xy, 0));
	Deltas[8] = double(f16tof32(Deltas16.x & 0xFFFF));
	Deltas[9] = double(f16tof32(Deltas16.x >> 16));
	Deltas[10] = double(f16tof32(Deltas16.y & 0xFFFF));
	Deltas[11] = double(f16tof32(Deltas16.y >> 16));
	Deltas[12] = double(f16tof32(Deltas16.z & 0xFFFF));
	Deltas[13] = double(f16tof32(Deltas16.z >> 16));
	Deltas[14] = double(f16tof32(Deltas16.w & 0xFFFF));
	Deltas[15] = double(f16tof32(Deltas16.w >> 16));

	uint4 Deltas20 = DeltasC.Load(int3(IN.Position.xy, 0));
	Deltas[16] = double(f16tof32(Deltas20.x & 0xFFFF));
	Deltas[17] = double(f16tof32(Deltas20.x >> 16));
	Deltas[18] = double(f16tof32(Deltas20.y & 0xFFFF));
	Deltas[19] = double(f16tof32(Deltas20.y >> 16));

	uint EnableFlags = Deltas20.z;
	uint NumSamples = countbits(EnableFlags);

#ifdef CLAMP_EDGES
	NumSamples = 20;
#endif

	if (NumSamples > 0)
	{
		double Height = 0.0;
		double Scale = 1.0 / NumSamples;
		for (int i = 0; i < 20; ++i)
		{
			if ((EnableFlags & (1 << i)) != 0)
			{
#ifdef HEIGHTMAP_DOUBLEPRECISION
				uint2 DoubleParts = HeightMap.Load(GetWrappedCoord2(int2(IN.Position.xy) + SampleOffsets[i], TextureWidth, TextureHeight));
				double RefHeight = asdouble(DoubleParts.x, DoubleParts.y) + Deltas[i];
#else
				double RefHeight = HeightMap.Load(GetWrappedCoord2(int2(IN.Position.xy) + SampleOffsets[i], TextureWidth, TextureHeight)) + Deltas[i];
#endif

				Height = fma(RefHeight, Scale, Height);
			}
		}

#ifdef HEIGHTMAP_DOUBLEPRECISION
		uint2 PackedHeight;
		asuint(Height, PackedHeight.x, PackedHeight.y);
		return PackedHeight;
#else
		return float(Height);
#endif
	}

#ifdef HEIGHTMAP_DOUBLEPRECISION
	return uint2(0, 0);
#else
	return 0;
#endif
}