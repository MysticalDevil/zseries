#include "ztmpfile.h"

#include <stdio.h>
#include <string.h>

static int expect_ok(int status, const char *what) {
  if (status != ZTMPFILE_OK) {
    fprintf(stderr, "%s failed: %s\n", what, ztmpfile_last_error_message());
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

  if (expect_ok(ztmpfile_tempdir_create("c-dir-", NULL, &dir), "tempdir_create")) return 1;
  if (expect_ok(ztmpfile_tempdir_path_copy(dir, &dir_path), "tempdir_path_copy")) return 1;
  if (dir_path == NULL || strstr(dir_path, "c-dir-") == NULL) {
    fprintf(stderr, "tempdir path missing expected prefix\n");
    return 1;
  }
  if (expect_ok(ztmpfile_tempdir_persist(dir, &kept_dir), "tempdir_persist")) return 1;
  ztmpfile_tempdir_destroy(dir);
  dir = NULL;
  ztmpfile_string_free(dir_path);
  dir_path = NULL;

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
  ztmpfile_tempfile_destroy(file);
  file = NULL;

  ztmpfile_string_free(file_path);
  ztmpfile_string_free(persisted_file);
  ztmpfile_string_free(kept_dir);
  return 0;
}
