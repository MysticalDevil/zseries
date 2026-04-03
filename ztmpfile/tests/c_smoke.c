#include "ztmpfile.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int expect_ok(int status, const char *what) {
  if (status != ZTMPFILE_OK) {
    fprintf(stderr, "%s failed: %s\n", what, ztmpfile_last_error_message());
    return 1;
  }
  return 0;
}

static int expect_status(int actual, int expected, const char *what) {
  if (actual != expected) {
    fprintf(stderr, "%s returned %d, expected %d (last error: %s)\n", what, actual, expected,
            ztmpfile_last_error_message());
    return 1;
  }
  return 0;
}

static int expect_nonempty_error(const char *what) {
  const char *msg = ztmpfile_last_error_message();
  if (msg == NULL || msg[0] == '\0') {
    fprintf(stderr, "%s did not populate last error message\n", what);
    return 1;
  }
  return 0;
}

int main(void) {
  ztmpfile_tempdir_t *dir = NULL;
  char *dir_path = NULL;
  char *kept_dir = NULL;
  ztmpfile_tempfile_t *file = NULL;
  char *file_path = NULL;
  char *persisted_file = NULL;

  if (expect_status(ztmpfile_tempdir_create("bad", NULL, NULL), ZTMPFILE_INVALID_ARGUMENT,
                    "tempdir_create(null out_handle)"))
    return 1;
  if (expect_nonempty_error("tempdir_create(null out_handle)")) return 1;

  if (expect_status(ztmpfile_tempdir_path_copy(NULL, &dir_path), ZTMPFILE_INVALID_ARGUMENT,
                    "tempdir_path_copy(null handle)"))
    return 1;
  if (expect_nonempty_error("tempdir_path_copy(null handle)")) return 1;

  if (expect_status(ztmpfile_tempfile_persist(NULL, "ignored", &persisted_file), ZTMPFILE_INVALID_ARGUMENT,
                    "tempfile_persist(null handle)"))
    return 1;
  if (expect_nonempty_error("tempfile_persist(null handle)")) return 1;

  if (expect_ok(ztmpfile_tempdir_create("c-dir-", NULL, &dir), "tempdir_create")) return 1;
  if (expect_ok(ztmpfile_tempdir_path_copy(dir, &dir_path), "tempdir_path_copy")) return 1;
  if (dir_path == NULL || strstr(dir_path, "c-dir-") == NULL) {
    fprintf(stderr, "tempdir path missing expected prefix\n");
    return 1;
  }
  if (expect_ok(ztmpfile_tempdir_persist(dir, &kept_dir), "tempdir_persist")) return 1;
  if (kept_dir == NULL) {
    fprintf(stderr, "tempdir_persist returned null kept path\n");
    return 1;
  }
  ztmpfile_tempdir_destroy(dir);
  dir = NULL;
  ztmpfile_string_free(dir_path);
  dir_path = NULL;

  if (access(kept_dir, F_OK) != 0) {
    fprintf(stderr, "kept tempdir does not exist after persist\n");
    return 1;
  }

  if (expect_ok(ztmpfile_tempfile_create("c-file-", kept_dir, &file), "tempfile_create")) return 1;
  if (expect_ok(ztmpfile_tempfile_path_copy(file, &file_path), "tempfile_path_copy")) return 1;
  if (file_path == NULL || strstr(file_path, "c-file-") == NULL) {
    fprintf(stderr, "tempfile path missing expected prefix\n");
    return 1;
  }

  char target_path[2048];
  snprintf(target_path, sizeof(target_path), "%s/persisted.bin", kept_dir);
  if (expect_ok(ztmpfile_tempfile_persist(file, target_path, &persisted_file), "tempfile_persist")) return 1;
  if (strcmp(persisted_file, target_path) != 0) {
    fprintf(stderr, "persisted tempfile path mismatch\n");
    return 1;
  }

  if (access(persisted_file, F_OK) != 0) {
    fprintf(stderr, "persisted tempfile does not exist\n");
    return 1;
  }

  if (expect_status(ztmpfile_tempfile_persist(file, target_path, &dir_path), ZTMPFILE_ALREADY_CLOSED,
                    "tempfile_persist(second persist)"))
    return 1;
  if (expect_nonempty_error("tempfile_persist(second persist)")) return 1;

  ztmpfile_tempfile_destroy(file);
  file = NULL;

  ztmpfile_tempfile_destroy(NULL);
  ztmpfile_tempdir_destroy(NULL);

  ztmpfile_string_free(file_path);
  ztmpfile_string_free(persisted_file);
  remove(target_path);
  rmdir(kept_dir);
  ztmpfile_string_free(kept_dir);
  return 0;
}
