// ====== 4-Pass Volumetric Fog DX9 / SM3.0 ======

float4x4 gWorld, gView, gProj;
float2 gInvTexSize = float2(1.0 / 1600.0, 1.0 / 900.0);

// ---------- Pass 1: OPAQUE (cube.x) ----------
texture gDiffuse;
sampler2D SDiff = sampler_state
{
    Texture = <gDiffuse>;
    MinFilter = ANISOTROPIC;
    MagFilter = ANISOTROPIC;
    MipFilter = LINEAR;
    MaxAnisotropy = 8;
    AddressU = Wrap;
    AddressV = Wrap;
};

float4 VS_Opaque(float3 pos : POSITION0, float2 uv : TEXCOORD0,
                 out float2 oUV : TEXCOORD0) : POSITION0
{
    float4 w = mul(float4(pos, 1), gWorld);
    float4 v = mul(w, gView);
    float4 h = mul(v, gProj);
    oUV = uv;
    return h;
}

float4 PS_Opaque(float2 uv : TEXCOORD0) : COLOR0
{
    return tex2D(SDiff, uv);
}

technique Technique_Opaque
{
    pass P0
    {
        CullMode = CCW;
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = LESSEQUAL;
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_Opaque();
        PixelShader = compile ps_3_0 PS_Opaque();
    }
}

// ---------- Pass 2: FOG FRONT DEPTH (前面深度をRTに書き込み) ----------
float4 VS_ScreenUV(float3 pos : POSITION0,
                   out float2 oUV : TEXCOORD0,
                   out float oEyeZ : TEXCOORD1) : POSITION0
{
    float4 w = mul(float4(pos, 1), gWorld);
    float4 v = mul(w, gView);
    float4 h = mul(v, gProj);

    // 線形視点空間Z（左手系なので遠くほど大きい値）
    oEyeZ = v.z;
    
    // スクリーン座標系UV
    float2 uv = h.xy / h.w;
    uv = uv * float2(0.5, -0.5) + 0.5;
    uv += 0.5 * gInvTexSize;
    oUV = uv;
    return h;
}

float4 PS_WriteFrontZ(float2 uv : TEXCOORD0, float eyeZ : TEXCOORD1) : COLOR0
{
    return float4(eyeZ, 0, 0, 1); // R32Fを想定
}

technique Technique_FrontDepth
{
    pass P0
    {
        CullMode = CCW; // 前面（表面）を描画
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = LESSEQUAL; // 通常のZテスト
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_WriteFrontZ();
    }
}

// ---------- Pass 3: FOG BACK DEPTH (後面深度をRTに書き込み) ----------
float4 PS_WriteBackZ(float2 uv : TEXCOORD0, float eyeZ : TEXCOORD1) : COLOR0
{
    return float4(eyeZ, 0, 0, 1); // R32Fを想定
}

technique Technique_BackDepth
{
    pass P0
    {
        CullMode = CW; // 後面（裏面）を描画するため裏面カリングを無効化（CCW→CW）
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = GREATER; // depth=0でクリアしているため、GREATER を使用
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_WriteBackZ();
    }
}

// ---------- Pass 4: FOG COMPOSITE (前面・後面深度を使ってフォグを合成) ----------
texture gFrontDepthTex; // 前面Z
texture gBackDepthTex; // 後面Z

sampler2D SFront = sampler_state
{
    Texture = <gFrontDepthTex>;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = NONE;
    AddressU = Clamp;
    AddressV = Clamp;
};

sampler2D SBack = sampler_state
{
    Texture = <gBackDepthTex>;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = NONE;
    AddressU = Clamp;
    AddressV = Clamp;
};

float gSigmaT = 0.6;
float3 gFogColor = float3(1, 1, 1);

/* 
float4 PS_FogComposite(float2 uv : TEXCOORD0, float eyeZFront : TEXCOORD1) : COLOR0
{
    float frontZ = tex2D(SFront, uv).r;
    float backZ = tex2D(SBack, uv).r;
    
    // フォグボリュームに入っていない場合は何も描画しない
    if (frontZ <= 0.0 || backZ <= 0.0)
    {
        discard;
    }
    
    // フォグの厚み（後面Z - 前面Z）
    float thickness = backZ - frontZ;
    
    // 厚みが負の場合（前後関係がおかしい場合）は描画しない
    if (thickness < 0.0)
    {
        discard;
    }
    
    // Beer-Lambert則によるアルファ値計算
    float alpha = saturate(1.0 - exp(-gSigmaT * thickness));
    
    // より濃いフォグ効果のための調整
    alpha = pow(alpha, 2.0);
    
    // Pre-multiplied alpha
    float3 col = gFogColor * alpha;
    return float4(col, alpha);
}
*/

// 中心だけ濃くする
// 追加：球中心(ビュー空間)と半径・鋭さ
float3 gSphereCenterVS;
float gSphereRadius = 1.0;
float gCenterSharpness = 10.0; // 2〜6 くらいで調整

float4 PS_FogComposite(float2 uv : TEXCOORD0, float eyeZFront : TEXCOORD1) : COLOR0
{
    float frontZ = tex2D(SFront, uv).r;
    float backZ = tex2D(SBack, uv).r;
    if (frontZ <= 0 || backZ <= 0 || backZ <= frontZ)
        discard;

    // ビュー空間位置を復元（LH）
    float2 ndc = float2(uv.x * 2 - 1, 1 - uv.y * 2);
    float invP11 = 1.0 / gProj._11, invP22 = 1.0 / gProj._22;
    float3 Pfront = float3(ndc.x * frontZ * invP11, ndc.y * frontZ * invP22, frontZ);
    float3 Pback = float3(ndc.x * backZ * invP11, ndc.y * backZ * invP22, backZ);
    float thickness = length(Pback - Pfront);
    float3 Pmid = 0.5 * (Pfront + Pback);

    // 中心ウェイト：中心 r=0 で1、境界 r=R で0
    float r = length(Pmid - gSphereCenterVS);
    float w = saturate(1.0 - (r * r) / (gSphereRadius * gSphereRadius));
    w = pow(w, gCenterSharpness); // 中心だけを強調

    // Beer–Lambert（密度を重み付けしてから積分）
    float sigma = gSigmaT * w;
    float alpha = saturate(1.0 - exp(-sigma * thickness));

    float3 col = gFogColor * alpha; // premultiplied
    return float4(col, alpha);
}

technique Technique_FogComposite
{
    pass P0
    {
        CullMode = CCW; // 前面を基準にして合成
        ZEnable = TRUE;
        ZWriteEnable = FALSE;
        ZFunc = LESSEQUAL;
        AlphaBlendEnable = TRUE;
        SrcBlend = ONE;
        DestBlend = INVSRCALPHA; // Pre-multiplied alpha blending
        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_FogComposite();
    }
}

// ---------- Alternative: フォグコンポジット（フルスクリーンクワッド用）----------
// フォグボリュームのジオメトリを使わずに、フルスクリーンクワッドで合成する場合

float4 VS_FullScreen(float3 pos : POSITION0, out float2 oUV : TEXCOORD0) : POSITION0
{
    oUV = pos.xy * 0.5 + 0.5;
    oUV.y = 1.0 - oUV.y; // UV座標系を合わせる
    return float4(pos.xy, 0, 1);
}

float4 PS_FullScreenFogComposite(float2 uv : TEXCOORD0) : COLOR0
{
    float frontZ = tex2D(SFront, uv).r;
    float backZ = tex2D(SBack, uv).r;
    
    // フォグボリュームに入っていない場合は透明
    if (frontZ <= 0.0 || backZ <= 0.0)
    {
        return float4(0, 0, 0, 0);
    }
    
    // フォグの厚み
    float thickness = backZ - frontZ;
    if (thickness < 0.0)
    {
        return float4(0, 0, 0, 0);
    }
    
    // Beer-Lambert則
    float alpha = saturate(1.0 - exp(-gSigmaT * thickness));
    alpha = pow(alpha, 2.0);
    
    // Pre-multiplied alpha
    float3 col = gFogColor * alpha;
    return float4(col, alpha);
}

technique Technique_FullScreenFogComposite
{
    pass P0
    {
        CullMode = None;
        ZEnable = FALSE;
        ZWriteEnable = FALSE;
        AlphaBlendEnable = TRUE;
        SrcBlend = ONE;
        DestBlend = INVSRCALPHA;
        VertexShader = compile vs_3_0 VS_FullScreen();
        PixelShader = compile ps_3_0 PS_FullScreenFogComposite();
    }
}