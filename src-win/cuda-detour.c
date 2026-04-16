#include "plat.h"
#include <windows.h>
#include <detours.h>

#include "cuda-hooks-shared.h"

static inline bool install_hook_entrys(HMODULE h, HookEntry *hooks, size_t num_hooks) {
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    int status;

    for (int i = 0; i < num_hooks; i++) {
        *hooks[i].true_ptr = (void*)GetProcAddress(h, hooks[i].name);
        if (!*hooks[i].true_ptr ||
            DetourAttach(hooks[i].true_ptr, hooks[i].hook_ptr) != 0) {
            log(ERROR, "%s: Hook %s failed %p", __func__, hooks[i].name, *hooks[i].true_ptr);
            DetourTransactionAbort();
            return false;
        }
    }

    status = (int)DetourTransactionCommit();
    if (status != 0) {
        log(ERROR, "%s: DetourTransactionCommit failed: %d", __func__, status);
        return false;
    }

    log(DEBUG, "%s: hooks successfully installed\n", __func__);
    return true;
}

bool aimdo_setup_hooks() {
    HMODULE h_real_cuda = GetModuleHandleA("nvcuda64.dll");
    if (h_real_cuda == NULL) {
        h_real_cuda = GetModuleHandleA("nvcuda.dll");
    }

    if (h_real_cuda == NULL) {
        log(ERROR, "%s: nvcuda driver not found in process memory", __func__);
        return false;
    }

    log(INFO, "%s: found driver at %p, installing %zu hooks\n",
        __func__, h_real_cuda, sizeof(hooks) / sizeof(HookEntry));

    return install_hook_entrys(h_real_cuda, (HookEntry*)hooks, sizeof(hooks) / sizeof(HookEntry));
}

void aimdo_teardown_hooks() {
    int status;

    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());

    for (int i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++) {
        /* Only detach if we actually successfully resolved the pointer */
        if (*hooks[i].true_ptr) {
            DetourDetach(hooks[i].true_ptr, hooks[i].hook_ptr);
        }
    }

    status = (int)DetourTransactionCommit();
    if (status != 0) {
        log(ERROR, "%s: DetourDetach failed: %d", __func__, status);
    } else {
        log(DEBUG, "%s: hooks successfully removed\n", __func__);
    }
}
