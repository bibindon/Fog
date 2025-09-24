#pragma comment( lib, "d3d9.lib" )
#if defined(DEBUG) || defined(_DEBUG)
#pragma comment( lib, "d3dx9d.lib" )
#else
#pragma comment( lib, "d3dx9.lib" )
#endif

#include <d3d9.h>
#include <d3dx9.h>
#include <string>
#include <tchar.h>
#include <cassert>
#include <crtdbg.h>
#include <vector>

#define SAFE_RELEASE(p) { if (p) { (p)->Release(); (p) = NULL; } }

const int WINDOW_SIZE_W = 1600;
const int WINDOW_SIZE_H = 900;

LPDIRECT3D9 g_pD3D = NULL;
LPDIRECT3DDEVICE9 g_pd3dDevice = NULL;
LPD3DXFONT g_pFont = NULL;
LPD3DXMESH g_pMesh = NULL;
std::vector<D3DMATERIAL9> g_pMaterials;
DWORD g_dwNumMaterials = 0;
LPD3DXEFFECT g_pEffect = NULL;
bool g_bClose = false;

// AABB 情報（OS）
D3DXVECTOR3 g_BoxCenterOS(0, 0, 0);
D3DXVECTOR3 g_BoxHalfExtent(0.5f, 0.5f, 0.5f);

static void TextDraw(LPD3DXFONT pFont, TCHAR* text, int X, int Y);
static void InitD3D(HWND hWnd);
static void Cleanup();
static void Render();
LRESULT WINAPI MsgProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

extern int WINAPI _tWinMain(_In_ HINSTANCE hInstance,
                            _In_opt_ HINSTANCE hPrevInstance,
                            _In_ LPTSTR lpCmdLine,
                            _In_ int nCmdShow);

// メッシュの OS AABB を計算し、中心と半径を得る
static void ComputeMeshAABB_OS(LPD3DXMESH mesh, D3DXVECTOR3& center, D3DXVECTOR3& halfExtent)
{
    LPDIRECT3DVERTEXBUFFER9 vb = NULL;
    HRESULT hr = mesh->GetVertexBuffer(&vb);
    assert(SUCCEEDED(hr));

    void* pData = NULL;
    hr = vb->Lock(0, 0, &pData, D3DLOCK_READONLY);
    assert(SUCCEEDED(hr));

    D3DVERTEXELEMENT9 decl[MAX_FVF_DECL_SIZE];
    hr = mesh->GetDeclaration(decl);
    assert(SUCCEEDED(hr));

    UINT posOffset = 0;
    for (int i = 0; decl[i].Stream != 0xFF; ++i)
    {
        if (decl[i].Usage == D3DDECLUSAGE_POSITION && decl[i].UsageIndex == 0)
        {
            posOffset = decl[i].Offset;
            break;
        }
    }

    const UINT stride = mesh->GetNumBytesPerVertex();
    const BYTE* base = static_cast<const BYTE*>(pData) + posOffset;
    D3DXVECTOR3 vmin, vmax;

    hr = D3DXComputeBoundingBox(
        reinterpret_cast<const D3DXVECTOR3*>(base),
        mesh->GetNumVertices(),
        stride,
        &vmin,
        &vmax);
    assert(SUCCEEDED(hr));

    vb->Unlock();
    SAFE_RELEASE(vb);

    center = (vmin + vmax) * 0.5f;
    halfExtent = (vmax - vmin) * 0.5f;
}

int WINAPI _tWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPTSTR lpCmdLine,
                     _In_ int nCmdShow)
{
    _CrtSetDbgFlag(_CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF);

    WNDCLASSEX wc { };
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_CLASSDC;
    wc.lpfnWndProc = MsgProc;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = _T("Window1");

    ATOM atom = RegisterClassEx(&wc);
    assert(atom != 0);

    RECT rect;
    SetRect(&rect, 0, 0, WINDOW_SIZE_W, WINDOW_SIZE_H);
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);
    HWND hWnd = CreateWindow(_T("Window1"),
                             _T("Analytic Volumetric Box (DX9)"),
                             WS_OVERLAPPEDWINDOW,
                             CW_USEDEFAULT,
                             CW_USEDEFAULT,
                             rect.right - rect.left,
                             rect.bottom - rect.top,
                             NULL, NULL, wc.hInstance, NULL);

    InitD3D(hWnd);
    ShowWindow(hWnd, SW_SHOWDEFAULT);
    UpdateWindow(hWnd);

    MSG msg;
    while (true)
    {
        if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
        {
            DispatchMessage(&msg);
        }
        else
        {
            Sleep(16);
            Render();
        }
        if (g_bClose) break;
    }

    Cleanup();
    UnregisterClass(_T("Window1"), wc.hInstance);
    return 0;
}

void TextDraw(LPD3DXFONT pFont, TCHAR* text, int X, int Y)
{
    RECT rect = { X, Y, 0, 0 };
    HRESULT hr = pFont->DrawText(NULL, text, -1, &rect,
                                 DT_LEFT | DT_NOCLIP,
                                 D3DCOLOR_ARGB(255, 0, 0, 0));
    assert((int)hr >= 0);
}

void InitD3D(HWND hWnd)
{
    HRESULT hr;

    g_pD3D = Direct3DCreate9(D3D_SDK_VERSION);
    assert(g_pD3D);

    D3DPRESENT_PARAMETERS d3dpp = {};
    d3dpp.Windowed = TRUE;
    d3dpp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    d3dpp.BackBufferFormat = D3DFMT_UNKNOWN;
    d3dpp.EnableAutoDepthStencil = TRUE;
    d3dpp.AutoDepthStencilFormat = D3DFMT_D16;
    d3dpp.hDeviceWindow = hWnd;

    hr = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                              D3DCREATE_HARDWARE_VERTEXPROCESSING,
                              &d3dpp, &g_pd3dDevice);
    if (FAILED(hr))
    {
        hr = g_pD3D->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hWnd,
                                  D3DCREATE_SOFTWARE_VERTEXPROCESSING,
                                  &d3dpp, &g_pd3dDevice);
        assert(SUCCEEDED(hr));
    }

    hr = D3DXCreateFont(g_pd3dDevice, 20, 0, FW_HEAVY, 1, FALSE,
                        SHIFTJIS_CHARSET, OUT_TT_ONLY_PRECIS,
                        CLEARTYPE_NATURAL_QUALITY, FF_DONTCARE,
                        _T("ＭＳ ゴシック"), &g_pFont);
    assert(SUCCEEDED(hr));

    // 立方体メッシュ読み込み
    LPD3DXBUFFER pMtrlBuf = NULL;
    hr = D3DXLoadMeshFromX(_T("cube.x"),
                           D3DXMESH_SYSTEMMEM,
                           g_pd3dDevice,
                           NULL,
                           &pMtrlBuf,
                           NULL,
                           &g_dwNumMaterials,
                           &g_pMesh);
    assert(SUCCEEDED(hr));
    if (pMtrlBuf) pMtrlBuf->Release(); // 材質・テクスチャ不要

    // AABB（OS）を計算 → 中心と半径を保持
    ComputeMeshAABB_OS(g_pMesh, g_BoxCenterOS, g_BoxHalfExtent);

    // エフェクト
    hr = D3DXCreateEffectFromFile(g_pd3dDevice,
                                  _T("simple.fx"),
                                  NULL, NULL,
                                  D3DXSHADER_DEBUG, NULL,
                                  &g_pEffect, NULL);
    assert(SUCCEEDED(hr));

    // レンダステート（プリマルチ“over”）
    g_pd3dDevice->SetRenderState(D3DRS_ZENABLE, TRUE);
    g_pd3dDevice->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    g_pd3dDevice->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    g_pd3dDevice->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
    g_pd3dDevice->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
    g_pd3dDevice->SetRenderState(D3DRS_CULLMODE, D3DCULL_CCW); // 規定でOK
}

void Cleanup()
{
    SAFE_RELEASE(g_pMesh);
    SAFE_RELEASE(g_pEffect);
    SAFE_RELEASE(g_pFont);
    SAFE_RELEASE(g_pd3dDevice);
    SAFE_RELEASE(g_pD3D);
}

void Render()
{
    HRESULT hr;

    static float t = 0.0f;
    t += 0.02f;

    // カメラ（少し周回）
    D3DXVECTOR3 eye(10.0f * sinf(t), 10.0f, -10.0f * cosf(t));
    D3DXVECTOR3 at(0, 0, 0);
    D3DXVECTOR3 up(0, 1, 0);

    D3DXMATRIX mWorld, mView, mProj, mInvWorld;
    D3DXMatrixIdentity(&mWorld);
    D3DXMatrixInverse(&mInvWorld, NULL, &mWorld);
    D3DXMatrixLookAtLH(&mView, &eye, &at, &up);
    D3DXMatrixPerspectiveFovLH(&mProj, D3DXToRadian(45),
                               (float)WINDOW_SIZE_W / WINDOW_SIZE_H,
                               0.5f, 1000.0f);

    // 画面クリア
    hr = g_pd3dDevice->Clear(0, NULL,
                             D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
                             D3DCOLOR_XRGB(100, 100, 100), 1.0f, 0);
    assert(SUCCEEDED(hr));

    hr = g_pd3dDevice->BeginScene();
    assert(SUCCEEDED(hr));

    // UI
//    TextDraw(g_pFont, L"Analytic Volumetric Box (Premultiplied)", 10, 10);

    // エフェクト定数セット
    g_pEffect->SetTechnique("TechniqueVolumeBox");
    g_pEffect->SetMatrix("gWorld", &mWorld);
    g_pEffect->SetMatrix("gInvWorld", &mInvWorld);
    g_pEffect->SetMatrix("gView", &mView);
    g_pEffect->SetMatrix("gProj", &mProj);
    g_pEffect->SetVector("gCameraPosW", (D3DXVECTOR4*)&eye);

    g_pEffect->SetVector("gBoxCenterOS", (D3DXVECTOR4*)&g_BoxCenterOS);
    g_pEffect->SetVector("gBoxHalfExtent", (D3DXVECTOR4*)&g_BoxHalfExtent);

    // 濃さと色（好みで調整）
    D3DXVECTOR4 fogColor(1, 1, 1, 1);
    g_pEffect->SetVector("gFogColor", &fogColor);
    g_pEffect->SetFloat("gSigmaT", 0.5f);

    UINT nPass = 0;
    hr = g_pEffect->Begin(&nPass, 0);
    assert(SUCCEEDED(hr));
    hr = g_pEffect->BeginPass(0);
    assert(SUCCEEDED(hr));

    // 立方体メッシュを“プロキシ”として描く（サブセット数は気にせず全て描く）
    for (DWORD i = 0; i < g_dwNumMaterials; ++i)
    {
        g_pEffect->CommitChanges();
        hr = g_pMesh->DrawSubset(i);
        assert(SUCCEEDED(hr));
    }

    g_pEffect->EndPass();
    g_pEffect->End();

    hr = g_pd3dDevice->EndScene();
    assert(SUCCEEDED(hr));

    hr = g_pd3dDevice->Present(NULL, NULL, NULL, NULL);
    assert(SUCCEEDED(hr));
}

LRESULT WINAPI MsgProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg)
    {
    case WM_DESTROY:
        PostQuitMessage(0);
        g_bClose = true;
        return 0;
    }
    return DefWindowProc(hWnd, msg, wParam, lParam);
}
