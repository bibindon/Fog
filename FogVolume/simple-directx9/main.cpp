#pragma comment(lib,"d3d9.lib")
#if defined(DEBUG) || defined(_DEBUG)
#pragma comment(lib,"d3dx9d.lib")
#else
#pragma comment(lib,"d3dx9.lib")
#endif

#include <d3d9.h>
#include <d3dx9.h>
#include <tchar.h>
#include <cassert>

#define SAFE_RELEASE(p) do{ if(p){ (p)->Release(); (p)=NULL; } }while(0)

const int WINDOW_W = 1600;
const int WINDOW_H = 900;

LPDIRECT3D9         g_pD3D = NULL;
LPDIRECT3DDEVICE9   g_pd3d = NULL;

LPD3DXMESH          g_meshCube = NULL;   // 通常メッシュ（cube.x）
LPD3DXMESH          g_meshSphere = NULL;   // フォグ用メッシュ（sphere.blend.x）

LPDIRECT3DTEXTURE9  g_texGrass = NULL;   // cube 用テクスチャ（grass.png）

LPD3DXEFFECT        g_fx = NULL;

// 背面Z用の RT と、専用の DS（シーンDSを壊さないため）
LPDIRECT3DTEXTURE9  g_rtBackDepth = NULL;  // R32F or A16B16G16R16F
LPDIRECT3DSURFACE9  g_surfBackRT = NULL;
LPDIRECT3DSURFACE9  g_dsBackPass = NULL;

bool g_quit = false;

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_DESTROY) { PostQuitMessage(0); g_quit = true; return 0; }
    return DefWindowProc(hWnd, msg, wp, lp);
}

void CreateBackDepthTargets(int w, int h)
{
    // RT
    HRESULT hr = D3DXCreateTexture(g_pd3d, w, h, 1,
                                   D3DUSAGE_RENDERTARGET,
                                   D3DFMT_R32F, D3DPOOL_DEFAULT,
                                   &g_rtBackDepth);
    if (FAILED(hr))
    {
        hr = D3DXCreateTexture(g_pd3d, w, h, 1,
                               D3DUSAGE_RENDERTARGET,
                               D3DFMT_A16B16G16R16F, D3DPOOL_DEFAULT,
                               &g_rtBackDepth);
        assert(SUCCEEDED(hr));
    }
    hr = g_rtBackDepth->GetSurfaceLevel(0, &g_surfBackRT);
    assert(SUCCEEDED(hr));

    // 背面パス専用の DS（シーン深度を消さない）
    hr = g_pd3d->CreateDepthStencilSurface(
        w, h, D3DFMT_D24S8, D3DMULTISAMPLE_NONE, 0, TRUE, &g_dsBackPass, NULL);
    assert(SUCCEEDED(hr));
}

static DWORD GetSubsetCount(LPD3DXMESH m)
{
    DWORD n = 0;
    if (!m) return 0;
    m->GetAttributeTable(NULL, &n);
    return n ? n : 1;
}

void Init(HWND hWnd)
{
    HRESULT hr;

    g_pD3D = Direct3DCreate9(D3D_SDK_VERSION);
    assert(g_pD3D);

    D3DPRESENT_PARAMETERS pp = {};
    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_UNKNOWN;
    pp.EnableAutoDepthStencil = TRUE;
    pp.AutoDepthStencilFormat = D3DFMT_D24S8;
    pp.hDeviceWindow = hWnd;

    hr = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                              D3DCREATE_HARDWARE_VERTEXPROCESSING,
                              &pp, &g_pd3d);
    if (FAILED(hr))
    {
        hr = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                                  D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                                  &pp, &g_pd3d);
        assert(SUCCEEDED(hr));
    }

    // メッシュ読み込み
    hr = D3DXLoadMeshFromX(_T("cube.x"),
                           D3DXMESH_MANAGED, g_pd3d,
                           NULL, NULL, NULL, NULL, &g_meshCube);
    assert(SUCCEEDED(hr));

    hr = D3DXLoadMeshFromX(_T("sphere.blend.x"),
                           D3DXMESH_MANAGED, g_pd3d,
                           NULL, NULL, NULL, NULL, &g_meshSphere);
    assert(SUCCEEDED(hr));

    // 草テクスチャ
    hr = D3DXCreateTextureFromFile(g_pd3d, _T("grass.png"), &g_texGrass);
    assert(SUCCEEDED(hr));

    // エフェクト
    hr = D3DXCreateEffectFromFile(g_pd3d, _T("simple.fx"),
                                  NULL, NULL, D3DXSHADER_DEBUG,
                                  NULL, &g_fx, NULL);
    assert(SUCCEEDED(hr));

    // 背面Zターゲット
    CreateBackDepthTargets(WINDOW_W, WINDOW_H);

    // 合成用ブレンド（プリマルチ "over"）
    g_pd3d->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    g_pd3d->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
    g_pd3d->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
}

void Cleanup()
{
    SAFE_RELEASE(g_dsBackPass);
    SAFE_RELEASE(g_surfBackRT);
    SAFE_RELEASE(g_rtBackDepth);
    SAFE_RELEASE(g_texGrass);
    SAFE_RELEASE(g_meshSphere);
    SAFE_RELEASE(g_meshCube);
    SAFE_RELEASE(g_fx);
    SAFE_RELEASE(g_pd3d);
    SAFE_RELEASE(g_pD3D);
}

void Render()
{
    HRESULT hr;

    // カメラ
    static float t = 0.0f; t += 0.02f;
    D3DXVECTOR3 eye(8.0f * sinf(t), 5.0f, -8.0f * cosf(t));
    D3DXVECTOR3 at(0, 0, 0);
    D3DXVECTOR3 up(0, 1, 0);

    D3DXMATRIX mV, mP;
    D3DXMatrixLookAtLH(&mV, &eye, &at, &up);
    D3DXMatrixPerspectiveFovLH(&mP, D3DXToRadian(45.0f),
                               (float)WINDOW_W / WINDOW_H, 0.5f, 1000.0f);

    D3DXVECTOR2 invSz(1.0f / WINDOW_W, 1.0f / WINDOW_H);

    // --------- 1) Opaque: cube.x を原点に描画 ---------
    LPDIRECT3DSURFACE9 bb = NULL, dsScene = NULL;
    g_pd3d->GetRenderTarget(0, &bb);
    g_pd3d->GetDepthStencilSurface(&dsScene);

    g_pd3d->Clear(0, NULL, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, 0xFF808080, 1.0f, 0);
    g_pd3d->BeginScene();

    // world: Identity（(0,0,0)）
    D3DXMATRIX mWCube; D3DXMatrixIdentity(&mWCube);

    g_fx->SetTechnique("Technique_Opaque");
    g_fx->SetMatrix("gWorld", &mWCube);
    g_fx->SetMatrix("gView", &mV);
    g_fx->SetMatrix("gProj", &mP);
    g_fx->SetTexture("gDiffuse", g_texGrass);

    UINT nPass = 0; g_fx->Begin(&nPass, 0); g_fx->BeginPass(0);
    for (DWORD i = 0, n = GetSubsetCount(g_meshCube); i < n; ++i)
        g_meshCube->DrawSubset(i);
    g_fx->EndPass(); g_fx->End();

    g_pd3d->EndScene();

    // --------- 2) Fog Pass1: 背面Z（sphere を (1,1,1) へ） ---------
    g_pd3d->SetRenderTarget(0, g_surfBackRT);
    g_pd3d->SetDepthStencilSurface(g_dsBackPass);       // 専用DS
    D3DVIEWPORT9 vp = { 0,0,(DWORD)WINDOW_W,(DWORD)WINDOW_H,0.0f,1.0f };
    g_pd3d->SetViewport(&vp);

    g_pd3d->Clear(0, NULL, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, 0x00000000, 0.0f, 0);
    g_pd3d->BeginScene();

    D3DXMATRIX mWSphere;
    D3DXMatrixTranslation(&mWSphere, 1.0f, 1.0f, 1.0f);

    g_fx->SetTechnique("Technique_BackDepth");
    g_fx->SetMatrix("gWorld", &mWSphere);
    g_fx->SetMatrix("gView", &mV);
    g_fx->SetMatrix("gProj", &mP);
    g_fx->SetVector("gInvTexSize", (D3DXVECTOR4*)&invSz);

    g_fx->Begin(&nPass, 0); g_fx->BeginPass(0);
    for (DWORD i = 0, n = GetSubsetCount(g_meshSphere); i < n; ++i)
        g_meshSphere->DrawSubset(i);
    g_fx->EndPass(); g_fx->End();

    g_pd3d->EndScene();

    // --------- 3) Fog Pass2: 前面で厚み→合成（バックバッファへ） ---------
    g_pd3d->SetRenderTarget(0, bb);         // 戻す
    g_pd3d->SetDepthStencilSurface(dsScene);// シーン深度を維持（キューブで埋まっている）

    g_pd3d->BeginScene();

    g_fx->SetTechnique("Technique_FrontComposite");
    g_fx->SetMatrix("gWorld", &mWSphere);
    g_fx->SetMatrix("gView", &mV);
    g_fx->SetMatrix("gProj", &mP);
    g_fx->SetVector("gInvTexSize", (D3DXVECTOR4*)&invSz);

    // 色と濃さ
    D3DXVECTOR4 fogCol(1, 1, 1, 1);
    g_fx->SetVector("gFogColor", &fogCol);
    g_fx->SetFloat("gSigmaT", 0.6f);

    g_fx->SetTexture("gBackDepthTex", g_rtBackDepth);

    g_fx->Begin(&nPass, 0); g_fx->BeginPass(0);
    for (DWORD i = 0, n = GetSubsetCount(g_meshSphere); i < n; ++i)
        g_meshSphere->DrawSubset(i);
    g_fx->EndPass(); g_fx->End();

    g_pd3d->EndScene();

    // 表示
    g_pd3d->Present(NULL, NULL, NULL, NULL);

    SAFE_RELEASE(bb);
    SAFE_RELEASE(dsScene);
}

int APIENTRY _tWinMain(HINSTANCE hInst, HINSTANCE, LPTSTR, int)
{
    // Window
    WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0,0, hInst, NULL, NULL, NULL, NULL, _T("VolFog"), NULL };
    RegisterClassEx(&wc);
    RECT rc = { 0,0,WINDOW_W,WINDOW_H };
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hWnd = CreateWindow(_T("VolFog"), _T("Cube (opaque) + Sphere (volumetric fog)"),
                             WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                             rc.right - rc.left, rc.bottom - rc.top, NULL, NULL, hInst, NULL);
    ShowWindow(hWnd, SW_SHOWDEFAULT); UpdateWindow(hWnd);

    Init(hWnd);

    MSG msg; ZeroMemory(&msg, sizeof(msg));
    while (!g_quit)
    {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessage(&msg); }
        else { Render(); }
    }

    Cleanup();
    UnregisterClass(_T("VolFog"), hInst);
    return 0;
}
