float4x4 g_matWorld;
float4x4 g_matWorldView;
float4x4 g_matWorldViewProj;
float4 g_lightNormal = { 0.3f, 1.0f, 0.5f, 0.0f };
float3 g_ambient = { 0.5f, 0.75f, 1.0f };

texture texture1;
sampler textureSampler = sampler_state {
    Texture = (texture1);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
};

void VertexShader1(in  float4 inPosition  : POSITION,
                   in  float4 inNormal    : NORMAL0,
                   in  float4 inTexCood   : TEXCOORD0,

                   out float4 outPosition : POSITION,
                   out float4 outDiffuse  : COLOR0,
                   out float4 outTexCood  : TEXCOORD0,
                   out float3 outWorldPos : TEXCOORD1)
{
    outPosition = mul(inPosition, g_matWorldViewProj);

    float lightIntensity = dot(inNormal, g_lightNormal);
    outDiffuse.rgb = max(0, lightIntensity);
    outDiffuse.a = 1.0f;

    outTexCood = inTexCood;

    outWorldPos = mul(inPosition, g_matWorld);
}

void PixelShader1(in float4 inScreenColor : COLOR0,
                  in float2 inTexCood     : TEXCOORD0,
                  in float3 inWorldPos    : TEXCOORD1,

                  out float4 outColor     : COLOR)
{
    float4 workColor = (float4)0;
    workColor = tex2D(textureSampler, inTexCood);
    outColor = inScreenColor * workColor;

    // outColorをinEyeZが大きいほどg_ambientに近づくようにする

    // 0メートル以上は0.0
    // -10メートル以下は1.0
    float y = saturate((inWorldPos.y / 10) * -1.f);

    outColor.xyz = lerp(outColor.xyz, g_ambient, y);
}

technique Technique1
{
   pass Pass1
   {
      VertexShader = compile vs_2_0 VertexShader1();
      PixelShader = compile ps_2_0 PixelShader1();
   }
}
