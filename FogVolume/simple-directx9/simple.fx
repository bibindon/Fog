// ========= Analytic Volumetric Box (DX9 / vs_2_0, ps_2_0) =========
// 構造体は使わず、in/out セマンティクスのみで受け渡し

float4x4 gWorld;
float4x4 gView;
float4x4 gProj;
float4x4 gInvWorld;

float3 gCameraPosW;

float3 gBoxCenterOS = float3(0, 0, 0); // メッシュのローカル中心（AABBの中心）
float3 gBoxHalfExtent = float3(0.5, 0.5, 0.5); // AABB 半径

float3 gFogColor = float3(1.0, 1.0, 1.0); // 白煙
float gSigmaT = 1.0; // 濃さ（大きいほど不透明）

// --- VS: ワールド座標を PS に渡すだけ ---
float4 VS_VolBox(float3 pos : POSITION0,
                 out float3 oPosW : TEXCOORD0) : POSITION0
{
    float4 Pw = mul(float4(pos, 1), gWorld);
    oPosW = Pw.xyz;
    float4 Pv = mul(Pw, gView);
    return mul(Pv, gProj);
}

// --- PS: レイ × 有限直方体（スラブ法）→ 通過長 L → α ---
float4 PS_VolBox(float3 posW : TEXCOORD0) : COLOR0
{
    // ワールド→ローカル（箱はローカルAABBで判定）
    float3 Ow = gCameraPosW;
    float3 O = mul(float4(Ow, 1), gInvWorld).xyz - gBoxCenterOS;

    float3 Pw = posW;
    float3 P = mul(float4(Pw, 1), gInvWorld).xyz - gBoxCenterOS;

    float3 D = normalize(P - O);

    // スラブ法
    float3 invD = 1.0 / D;
    float3 t1 = (-gBoxHalfExtent - O) * invD;
    float3 t2 = (gBoxHalfExtent - O) * invD;

    float3 tMin = min(t1, t2);
    float3 tMax = max(t1, t2);

    float tNear = max(tMin.x, max(tMin.y, tMin.z));
    float tFar = min(tMax.x, min(tMax.y, tMax.z));

    if (tFar <= tNear || tFar <= 0.0)
        return float4(0, 0, 0, 0);

    // 視点が箱の外でも内でもOK
    if (tNear < 0.0)
        tNear = 0.0;

    float L = max(tFar - tNear, 0.0);

    // 均一媒質の減衰 → プリマルチ色
    float T = exp(-gSigmaT * L);
    float alpha = saturate(1.0 - T);

    // 境界線がくっきり出るのを防ぐ
    alpha = alpha * alpha;

    float3 col = gFogColor * alpha;

    return float4(col, alpha);
}

technique TechniqueVolumeBox
{
    pass P0
    {
        VertexShader = compile vs_3_0 VS_VolBox();
        PixelShader = compile ps_3_0 PS_VolBox();
        // D3D 側で:
        // ZEnable=TRUE, ZWriteEnable=FALSE,
        // AlphaBlend=TRUE, Src=ONE, Dest=INV_SRC_ALPHA
        // Cull はどちらでも可（規定のCCWでOK）
    }
}
