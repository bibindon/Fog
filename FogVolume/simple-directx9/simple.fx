// ================= Volumetric Fog by Front/Back Depth + Opaque Mesh (DX9 / SM3.0) =================
// Pass1: 背面の線形Z(eyeZ) を R32F RT に書き出す（ZFunc=GREATER, Depth=0 でクリア）
// Pass2: 前面で backZ - frontZ から厚みを出し、α=1-exp(-σ_t*L) でプリマルチ合成
// 追加: 通常の不透明メッシュ描画用 Technique_Opaque

float4x4 gWorld, gView, gProj;

// 画面サイズの逆数（半ピクセル補正用）
float2 gInvTexSize = float2(1.0 / 1600.0, 1.0 / 900.0);

// ----------------------- Opaque (cube.x 用) -----------------------
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
        AlphaBlendEnable = FALSE;

        VertexShader = compile vs_3_0 VS_Opaque();
        PixelShader = compile ps_3_0 PS_Opaque();
    }
}

// ----------------------- Volumetric Fog (sphere.blend.x 用) -----------------------

// 背面Zを書いた R32F / A16B16G16R16F テクスチャ
texture gBackDepthTex;
sampler2D SBack = sampler_state
{
    Texture = <gBackDepthTex>;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = NONE;
    AddressU = Clamp;
    AddressV = Clamp;
};

// フォグの濃さと色
float gSigmaT = 0.6; // 濁度（大きいほど濃い）
float3 gFogColor = float3(1, 1, 1); // 白煙

// 共通VS：スクリーンUVと線形Z(eyeZ)を出す
float4 VS_ScreenUV(
    float3 pos : POSITION0,
    out float2 oUV : TEXCOORD0,
    out float oEyeZ : TEXCOORD1) : POSITION0
{
    float4 w = mul(float4(pos, 1), gWorld);
    float4 v = mul(w, gView);
    float4 h = mul(v, gProj);

    // 左手系(LookAtLH)：奥へ行くほど v.z が大
    oEyeZ = v.z;

    float2 uv = h.xy / h.w; // NDC(-1..1)
    uv = uv * float2(0.5, -0.5) + 0.5;
    uv += 0.5 * gInvTexSize; // D3D9 半ピクセル補正
    oUV = uv;

    return h;
}

// P1: 背面の線形Zを書き出す
float4 PS_WriteBackZ(float2 uv : TEXCOORD0, float eyeZ : TEXCOORD1) : COLOR0
{
    return float4(eyeZ, 0, 0, 1); // R32F想定（.r を使用）
}

technique Technique_BackDepth
{
    pass P0
    {
        // 深度0クリア後に GREATER で描くと、最も奥（=値が大）の面が残る
        CullMode = None; // 巻き順に依らず両面描画
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = GREATER; // 重要
        AlphaBlendEnable = FALSE;

        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_WriteBackZ();
    }
}

// P2: 前面で厚みを計算して合成
float4 PS_FrontComposite(float2 uv : TEXCOORD0, float eyeZFront : TEXCOORD1) : COLOR0
{
    float backZ = tex2D(SBack, uv).r; // 背面の線形Z
    float thickness = backZ - eyeZFront; // 厚み（m）
    if (thickness < 0.0)
        thickness = 0.0;

    float alpha = 1.0 - exp(-gSigmaT * thickness); // Beer-Lambert
    alpha = saturate(alpha);
    
    alpha = pow(alpha, 4);

    float3 col = gFogColor * alpha; // プリマルチ色
    return float4(col, alpha);
}

technique Technique_FrontComposite
{
    pass P0
    {
        CullMode = None; // 両面描画、深度で前面のみ通る
        ZEnable = TRUE;
        ZWriteEnable = FALSE; // 合成なので書かない
        ZFunc = LESSEQUAL; // シーンの深度と比較

        // プリマルチ "over"
        AlphaBlendEnable = TRUE;
        SrcBlend = ONE;
        DestBlend = INVSRCALPHA;

        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_FrontComposite();
    }
}
