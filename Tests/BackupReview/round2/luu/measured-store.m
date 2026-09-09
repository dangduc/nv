#import <Foundation/Foundation.h>
#include <unistd.h>
#include <sys/stat.h>

// This wrapper observes the production store's POSIX reads. It does not alter
// bytes or errors. Plists are smaller than the archive fixture and excluded.
unsigned long long ReviewArchiveReadBytes;
static ssize_t ReviewRead(int descriptor, void *buffer, size_t size) {
    ssize_t count = read(descriptor, buffer, size);
    struct stat info;
    if (count > 0 && fstat(descriptor, &info) == 0 && info.st_size >= 1024 * 1024)
        ReviewArchiveReadBytes += (unsigned long long)count;
    return count;
}
#define read ReviewRead
#include "Sources/Storage/NVBackupStore.m"
#undef read
