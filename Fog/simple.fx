float4x4 matWorld;
float4x4 matWorldViewProj;
float4 lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float4 g_cameraPos = { 0.0f, 0.0f, 0.0f, 0.0f };

texture texture1;
sampler textureSampler = sampler_state {
    Texture = (texture1);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void vertex_shader(
    in  float4 in_position  : POSITION,
    in  float4 in_normal : NORMAL0,
    in  float4 in_texcood : TEXCOORD0,

    out float4 out_position : POSITION,
    out float4 out_diffuse : COLOR0,
    out float4 out_texcood : TEXCOORD0,
    out float4 fog : TEXCOORD1
    )
{
    // ワールド座標に変換
    float4 worldPos = mul(in_position, matWorld);

    // カメラからの距離をワールド空間で計算
    float distance = length(worldPos.xyz - g_cameraPos.xyz);

    out_position = mul(in_position, matWorldViewProj);

    float light_intensity = dot(in_normal, lightNormal);
    out_diffuse.rgb = max(0, light_intensity);
    out_diffuse.a = 1.0f;

    out_texcood = in_texcood;

    fog.rbg = 1.0f - ((15 - distance) / 15);
    fog.a = 1.0f;
}

// 霧はピクセルシェーダーでやらないと意味がない。
// 頂点シェーダーでやると、遠いほどくっきり見えるようになるだけ
void NoWorkingPixelShader(
    in float4 ScreenColor : COLOR0,
    in float2 in_texcood : TEXCOORD0,
    in float4 fog : TEXCOORD1,

    out float4 outColor : COLOR)
{
    float4 workColor = (float4)0;
    workColor = tex2D(textureSampler, in_texcood);
    outColor = (ScreenColor * workColor);
    outColor += fog/5;
}

technique BasicTec
{
   pass P0
   {
      VertexShader = compile vs_2_0 vertex_shader();
      PixelShader = compile ps_2_0 NoWorkingPixelShader();
   }
}
