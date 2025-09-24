// ====== Opaque + Volumetric Fog (Front/Back + SceneDepth clamp) DX9 / SM3.0 ======

float4x4 gWorld, gView, gProj;
float2 gInvTexSize = float2(1.0 / 1600.0, 1.0 / 900.0);

// ---------- OPAQUE (cube.x) ----------
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

// ZEqual でカラーだけ付ける（深度はPrepassで作成）
technique Technique_Opaque_ZEqual
{
    pass P0
    {
        CullMode = CCW;
        ZEnable = TRUE;
        ZWriteEnable = FALSE;
        ZFunc = EQUAL;
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_Opaque();
        PixelShader = compile ps_3_0 PS_Opaque();
    }
}

// ---------- SCENE DEPTH (linear eyeZ を R32F に) ----------
texture gDummy; // 使わない（形だけ）
float4 VS_SceneDepth(float3 pos : POSITION0,
                     out float2 oUV : TEXCOORD0,
                     out float oEyeZ : TEXCOORD1) : POSITION0
{
    float4 w = mul(float4(pos, 1), gWorld);
    float4 v = mul(w, gView);
    float4 h = mul(v, gProj);

    // 左手系(LookAtLH)：奥ほど v.z が大 → これを線形深度として使う
    oEyeZ = v.z;

    float2 uv = h.xy / h.w;
    uv = uv * float2(0.5, -0.5) + 0.5;
    uv += 0.5 * gInvTexSize;
    oUV = uv;
    return h;
}

float4 PS_WriteSceneZ(float2 uv : TEXCOORD0, float eyeZ : TEXCOORD1) : COLOR0
{
    return float4(eyeZ, 0, 0, 1); // R32Fを想定
}

technique Technique_SceneDepth
{
    pass P0
    {
        CullMode = CCW;
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = LESSEQUAL;
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_SceneDepth();
        PixelShader = compile ps_3_0 PS_WriteSceneZ();
    }
}

// ---------- VOLUMETRIC FOG (sphere.blend.x) ----------

texture gBackDepthTex; // 背面Z
texture gSceneDepthTex; // シーンZ
sampler2D SBack = sampler_state
{
    Texture = <gBackDepthTex>;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = NONE;
    AddressU = Clamp;
    AddressV = Clamp;
};
sampler2D SScene = sampler_state
{
    Texture = <gSceneDepthTex>;
    MinFilter = POINT;
    MagFilter = POINT;
    MipFilter = NONE;
    AddressU = Clamp;
    AddressV = Clamp;
};

float gSigmaT = 0.6;
float3 gFogColor = float3(1, 1, 1);

float4 VS_ScreenUV(float3 pos : POSITION0,
                   out float2 oUV : TEXCOORD0,
                   out float oEyeZ : TEXCOORD1) : POSITION0
{
    float4 w = mul(float4(pos, 1), gWorld);
    float4 v = mul(w, gView);
    float4 h = mul(v, gProj);

    oEyeZ = v.z; // 線形
    float2 uv = h.xy / h.w;
    uv = uv * float2(0.5, -0.5) + 0.5;
    uv += 0.5 * gInvTexSize;
    oUV = uv;
    return h;
}

// 背面Z 書き出し
float4 PS_WriteBackZ(float2 uv : TEXCOORD0, float eyeZ : TEXCOORD1) : COLOR0
{
    return float4(eyeZ, 0, 0, 1);
}

technique Technique_BackDepth
{
    pass P0
    {
        CullMode = None;
        ZEnable = TRUE;
        ZWriteEnable = TRUE;
        ZFunc = GREATER; // 深度0クリア前提
        AlphaBlendEnable = FALSE;
        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_WriteBackZ();
    }
}

// 前面で厚み→合成（sceneZ でクランプ）
float4 PS_FrontComposite(float2 uv : TEXCOORD0, float eyeZFront : TEXCOORD1) : COLOR0
{
    float backZ = tex2D(SBack, uv).r;
    float sceneZ = tex2D(SScene, uv).r;

    // シーンに何も無い画素は prepass で0のまま → "非常に遠い" とみなす
    if (sceneZ <= 0.0)
        sceneZ = 1e9;

    float endZ = min(backZ, sceneZ);
    float thickness = endZ - eyeZFront;
    if (thickness < 0.0)
    {
        thickness = 0.0;
    }

    float alpha = saturate(1.0 - exp(-gSigmaT * thickness));
    alpha = pow(alpha, 3);
    float3 col = gFogColor * alpha; // premultiplied
    return float4(col, alpha);
}

technique Technique_FrontComposite
{
    pass P0
    {
        CullMode = None;
        ZEnable = TRUE;
        ZWriteEnable = FALSE;
        ZFunc = LESSEQUAL;
        AlphaBlendEnable = TRUE;
        SrcBlend = ONE;
        DestBlend = INVSRCALPHA;
        VertexShader = compile vs_3_0 VS_ScreenUV();
        PixelShader = compile ps_3_0 PS_FrontComposite();
    }
}
