#pragma once

#if defined(_MSC_VER) && !defined(__clang__) && !defined(_Thread_local)
#define _Thread_local __declspec(thread)
#endif
