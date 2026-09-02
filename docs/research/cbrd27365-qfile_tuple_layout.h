/*
 * cbrd27365-qfile_tuple_layout.h — CBRD-27365 임시 리스트 튜플 포맷 명세 v0 의 코드 표현 (STUB, 컴파일 대상 아님)
 *
 * 명세: docs/research/cbrd27365-tuple-format-spec.md (지도 #179, 티켓 #180)
 * 실제 헤더는 src/query/qfile_tuple_layout.h 로 들어가며 서버·SA·클라이언트(cursor.c)가 공유한다.
 * 디스크립터 자료구조(#181)·접근자 API(#182)는 이 스텁이 고정한 상수·불변식 위에서 설계한다.
 */
#ifndef _QFILE_TUPLE_LAYOUT_H_
#define _QFILE_TUPLE_LAYOUT_H_

#include "object_representation.h"	/* OR_GET_INT, OR_PUT_INT, DB_ALIGN */

/* ------------------------------------------------------------------ */
/* D-180-1  튜플 헤더                                                   */
/* ------------------------------------------------------------------ */
#define QFILE_TUPLE_LEN_OFFSET            0
#define QFILE_TUPLE_PREV_LEN_OFFSET       4	/* backward_capable 리스트만 존재 */
#define QFILE_TUPLE_HDR_SIZE_FORWARD      4
#define QFILE_TUPLE_HDR_SIZE_BACKWARD     8
#define QFILE_TUPLE_ALIGN                 4	/* D-180-3: 상수. 튜플 시작·길이·data_off 모두 4의 배수 */

#define QFILE_TUPLE_HASNULL_BIT           0x80000000
#define QFILE_TUPLE_LENGTH_MASK           0x7FFFFFFF

/* 모든 길이 읽기는 이 매크로만 사용 (PR-1 에서 기존 QFILE_GET_TUPLE_LENGTH 를 이 정의로 교체) */
#define QFILE_GET_TUPLE_LENGTH(tpl)       ((int) (OR_GET_INT ((tpl) + QFILE_TUPLE_LEN_OFFSET) & QFILE_TUPLE_LENGTH_MASK))
#define QFILE_TUPLE_HAS_NULL(tpl)         ((OR_GET_INT ((tpl) + QFILE_TUPLE_LEN_OFFSET) & QFILE_TUPLE_HASNULL_BIT) != 0)
#define QFILE_PUT_TUPLE_LENGTH(tpl, len, has_null) \
  OR_PUT_INT ((tpl) + QFILE_TUPLE_LEN_OFFSET, ((len) & QFILE_TUPLE_LENGTH_MASK) | ((has_null) ? QFILE_TUPLE_HASNULL_BIT : 0))

/* prev_len 은 플래그 없는 순수 길이. backward_capable 리스트에서만 호출 가능 (호출자 assert) */
#define QFILE_GET_PREV_TUPLE_LENGTH(tpl)      OR_GET_INT ((tpl) + QFILE_TUPLE_PREV_LEN_OFFSET)
#define QFILE_PUT_PREV_TUPLE_LENGTH(tpl, len) OR_PUT_INT ((tpl) + QFILE_TUPLE_PREV_LEN_OFFSET, (len))

/* ------------------------------------------------------------------ */
/* D-180-2  널 비트맵 (1 = bound, 0 = NULL, 비트 i -> byte[i>>3] bit (i&7)) */
/* ------------------------------------------------------------------ */
#define QFILE_NULL_BITMAP_SIZE(type_cnt)  (((type_cnt) + 7) >> 3)

static inline bool
qfile_bitmap_is_null (const unsigned char *bits, int col)
{
  return (bits[col >> 3] & (1u << (col & 7))) == 0;
}

/* 첫 NULL 컬럼 (0-based). 비트맵은 has-null 튜플에만 존재하므로 0비트가 반드시 있다. type_cnt 로 캡. */
static inline int
qfile_bitmap_first_null (const unsigned char *bits, int type_cnt)
{
  int nbytes = QFILE_NULL_BITMAP_SIZE (type_cnt);
  int b;
  for (b = 0; b < nbytes; b++)
    {
      if (bits[b] != 0xFF)
	{
	  int res = (b << 3) + __builtin_ctz (~(unsigned) bits[b]);
	  return res < type_cnt ? res : type_cnt;
	}
    }
  return type_cnt;		/* 도달 불가 (불변식 2) */
}

/* ------------------------------------------------------------------ */
/* D-180-4/5  컬럼 부류와 정렬                                          */
/* ------------------------------------------------------------------ */
typedef enum
{
  QFILE_COL_FIXED = 0,		/* is_size_computed()==false : size=disksize, alignby 2|4 (8B 타입도 4, memcpy 읽기), data_* */
  QFILE_COL_VAR			/* is_size_computed()==true : 정렬 없음, 1B|4B 헤더, 단일 규칙 (D-180-5) */
} QFILE_COL_KIND;

/* 가변 컬럼의 접근 방식 — 포맷이 아닌 접근자 구현의 분기 (§6.2). finalize 시 pr_type 능력으로 결정 */
typedef enum
{
  QFILE_VAR_DIRECT = 0,		/* index_readval != NULL : 비정렬 본문을 index_readval/index_cmpdisk 로 직접 */
  QFILE_VAR_SCRATCH		/* index_readval == NULL : 본문 L 바이트를 8B 정렬 스크래치로 memcpy 후 data_* */
} QFILE_VAR_ACCESS;

/* 컬럼 단위 레이아웃 (D-180-3: off 는 data_off 기준, 상수 접두 밖은 -1) */
typedef struct qfile_col_layout QFILE_COL_LAYOUT;
struct qfile_col_layout
{
  QFILE_COL_KIND kind;
  QFILE_VAR_ACCESS var_access;	/* VAR 만 유효 */
  short size;			/* FIXED 만 유효 (disksize) */
  unsigned char alignby;	/* FIXED: 2|4 (D-180-4). VAR: 1 */
  int off;			/* 상수 오프셋 (data_off 기준) 또는 -1 */
};

/* 리스트 단위 레이아웃 (type_list 확장, #181 이 최종 형태를 정한다) */
typedef struct qfile_tuple_layout QFILE_TUPLE_LAYOUT;
struct qfile_tuple_layout
{
  int type_cnt;
  unsigned char hdr_size;	/* 4 or 8 (backward_capable) */
  unsigned char bitmap_size;	/* QFILE_NULL_BITMAP_SIZE(type_cnt) — 255B(2040 컬럼) 초과 시 int 로 승격 */
  unsigned char data_off[2];	/* [0]=no-null, [1]=has-null : ALIGN4(hdr_size + bitmap) (D-180-3) */
  int first_var_col;		/* 첫 가변 컬럼, 없으면 type_cnt */
  QFILE_COL_LAYOUT *col;	/* [type_cnt] */
};

/* ------------------------------------------------------------------ */
/* D-180-6  가변 길이 헤더 : bit7=0 -> 1B (L<=127), bit7=1 -> 4B ntohl & 0x7FFFFFFF */
/* ------------------------------------------------------------------ */
#define QFILE_VARHDR_SHORT_MAX            127
#define QFILE_VARHDR_LONG_BIT             0x80000000

static inline int
qfile_varhdr_size_for (int body_len)
{
  return body_len <= QFILE_VARHDR_SHORT_MAX ? 1 : 4;
}

/* 헤더 디코드: *hdr_len 에 1|4, 반환값은 본문 길이 */
static inline int
qfile_varhdr_decode (const char *p, int *hdr_len)
{
  unsigned char b0 = (unsigned char) *p;
  if ((b0 & 0x80) == 0)
    {
      *hdr_len = 1;
      return b0;
    }
  *hdr_len = 4;
  return (int) (OR_GET_INT (p) & QFILE_TUPLE_LENGTH_MASK);	/* OR_GET_INT 는 memcpy 기반 구현으로 교체 (#182) */
}

static inline void
qfile_varhdr_encode (char *p, int hdr_len, int body_len)
{
  if (hdr_len == 1)
    {
      *p = (char) body_len;
    }
  else
    {
      OR_PUT_INT (p, body_len | QFILE_VARHDR_LONG_BIT);
    }
}

/* ------------------------------------------------------------------ */
/* D-180-7  deform 캐시 (튜플/커서 단위)                                 */
/* ------------------------------------------------------------------ */
typedef struct qfile_deform_cache QFILE_DEFORM_CACHE;
struct qfile_deform_cache
{
  const char *tpl;		/* 캐시가 유효한 튜플 */
  int fast_limit;		/* min(first_var_col, first_null) */
  int next_col;			/* 증분 진행 위치 */
  int next_off;			/* 튜플 시작 기준 바이트 오프셋 */
};

/* 접근자 시그니처 (구현·명명은 #182):
 *   const char *qfile_tuple_value_ptr (const QFILE_TUPLE_LAYOUT *, const char *tpl, int col,
 *                                      QFILE_DEFORM_CACHE *, int *body_len, bool *is_null);
 *     - FIXED: 정렬된 본문 포인터, body_len=size (8B 타입은 memcpy 로 읽는다, SER-03)
 *     - VAR/DIRECT : 헤더 뒤 비정렬 본문 (index_readval(size=L) / index_cmpdisk 로만 소비)
 *     - VAR/SCRATCH: 접근자가 본문을 스레드 로컬 8B 정렬 스크래치로 memcpy 한 뒤 그 포인터 반환 (data_*)
 *   int qfile_tuple_size (layout, inputs[])           — 조립 1패스
 *   int qfile_tuple_fill (layout, inputs[], char *out, int size) — 조립 2패스 (len 워드·비트맵·값·패딩)
 *   int qfile_tuple_overwrite_fixed (layout, char *tpl, int col, const DB_VALUE *) — §9 in-place, assert 4개
 */

/* 불변식 요약 (§12): len%QFILE_TUPLE_ALIGN==0; has_null <=> 비트맵에 0비트; 후행 비트 0;
 * FIXED 위치%alignby==0; VAR 기록==L (DIRECT: index_lengthval, data_writeval 금지 / SCRATCH: data_lengthval, 스크래치 경유);
 * connect/append/duplicate 시 hdr_size·type_cnt 일치. */

#endif /* _QFILE_TUPLE_LAYOUT_H_ */
