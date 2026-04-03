#ifndef ZTMPFILE_H
#define ZTMPFILE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ztmpfile_tempdir ztmpfile_tempdir_t;
typedef struct ztmpfile_tempfile ztmpfile_tempfile_t;

typedef enum ztmpfile_status {
    ZTMPFILE_OK = 0,
    ZTMPFILE_INVALID_ARGUMENT = 1,
    ZTMPFILE_OUT_OF_MEMORY = 2,
    ZTMPFILE_IO_ERROR = 3,
    ZTMPFILE_ALREADY_CLOSED = 4,
    ZTMPFILE_INVALID_STATE = 5,
    ZTMPFILE_UNKNOWN_ERROR = 255
} ztmpfile_status_t;

const char *ztmpfile_last_error_message(void);
void ztmpfile_string_free(char *ptr);

int ztmpfile_tempdir_create(
    const char *prefix,
    const char *parent_dir,
    ztmpfile_tempdir_t **out_handle
);
int ztmpfile_tempdir_path_copy(
    ztmpfile_tempdir_t *handle,
    char **out_owned_path
);
int ztmpfile_tempdir_persist(
    ztmpfile_tempdir_t *handle,
    char **out_owned_path
);
void ztmpfile_tempdir_destroy(ztmpfile_tempdir_t *handle);

int ztmpfile_tempfile_create(
    const char *prefix,
    const char *parent_dir,
    ztmpfile_tempfile_t **out_handle
);
int ztmpfile_tempfile_path_copy(
    ztmpfile_tempfile_t *handle,
    char **out_owned_path
);
int ztmpfile_tempfile_persist(
    ztmpfile_tempfile_t *handle,
    const char *to_path,
    char **out_owned_path
);
void ztmpfile_tempfile_destroy(ztmpfile_tempfile_t *handle);

#ifdef __cplusplus
}
#endif

#endif

