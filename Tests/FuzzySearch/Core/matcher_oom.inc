/* The following sweeps fail every allocation ordinal reached by their clean
   baseline. Each run starts with a fresh engine so slab high-water caches do
   not hide a later allocation. Successful native allocation fallbacks must
   equal the clean result, including native rank diagnostics and order. */
static NVFZFStatus search_oom_case(NVFZFEngine *engine,
                                  const NVFZFCandidate *items, size_t count,
                                  const char *query, const NVFZFTerm *terms,
                                  size_t term_count, NVFZFSearchResult *result) {
  return query ? nvfzf_search(engine, items, count, query, strlen(query), NVFZF_NATIVE_FUZZY, NULL, result) :
    nvfzf_search_terms(engine, items, count, terms, term_count, NULL, result);
}

static void sweep_matcher_search(const char *label, const NVFZFCandidate *items,
                                 size_t count, const char *query,
                                 const NVFZFTerm *terms, size_t term_count) {
  reset_matcher_allocations(0);
  NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine, "%s baseline engine", label);
  reset_matcher_allocations(0);
  NVFZFSearchResult expected = {0};
  CHECK(search_oom_case(engine, items, count, query, terms, term_count, &expected) == NVFZF_OK,
        "%s baseline search", label);
  size_t allocations = atomic_load(&matcher_alloc_calls);
  CHECK(allocations > 0 && expected.count > 0, "%s must allocate and match", label);
  nvfzf_engine_free(engine);
  size_t errors = 0, fallbacks = 0;
  for (size_t failure = 1; failure <= allocations; failure++) {
    reset_matcher_allocations(0);
    engine = nvfzf_engine_create(); CHECK(engine, "%s fresh engine", label);
    reset_matcher_allocations(failure);
    NVFZFSearchResult result = {(void *)1, 42};
    NVFZFStatus status = search_oom_case(engine, items, count, query, terms, term_count, &result);
    if (status == NVFZF_OK) {
      compare_result(&result, &expected, label); fallbacks++;
    } else {
      CHECK(status == NVFZF_OUT_OF_MEMORY, "%s allocation %zu status %d", label, failure, status);
      CHECK(!result.matches && !result.count, "%s OOM never exposes partial list", label); errors++;
    }
    nvfzf_search_result_free(&result);
    reset_matcher_allocations(0);
    CHECK(search_oom_case(engine, items, count, query, terms, term_count, &result) == NVFZF_OK,
          "%s recovers after allocation %zu", label, failure);
    compare_result(&result, &expected, label);
    nvfzf_search_result_free(&result); nvfzf_engine_free(engine);
  }
  CHECK(errors > 0, "%s must expose fatal upstream allocation errors", label);
  printf("Upstream search OOM %-20s: %zu ordinals, %zu errors, %zu complete fallbacks.\n",
         label, allocations, errors, fallbacks);
  nvfzf_search_result_free(&expected);
}

static void compare_positions(const NVFZFPositions *actual, const NVFZFPositions *expected, const char *label) {
  CHECK(actual->matched == expected->matched && actual->count == expected->count,
        "%s positions membership/count", label);
  for (size_t i = 0; i < expected->count; i++)
    CHECK(actual->offsets[i] == expected->offsets[i], "%s position %zu", label, i);
}

static NVFZFStatus positions_oom_case(NVFZFEngine *engine, NVFZFCandidate input,
                                    const char *query, const NVFZFTerm *terms,
                                    size_t term_count, NVFZFPositions *positions) {
  return query ? nvfzf_positions(engine, input, query, strlen(query), NVFZF_NATIVE_FUZZY, NULL, positions) :
    nvfzf_positions_terms(engine, input, terms, term_count, NULL, positions);
}

static void sweep_matcher_positions(const char *label, NVFZFCandidate input,
                                    const char *query, const NVFZFTerm *terms, size_t term_count) {
  reset_matcher_allocations(0);
  NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine, "%s baseline engine", label);
  reset_matcher_allocations(0);
  NVFZFPositions expected = {0};
  CHECK(positions_oom_case(engine, input, query, terms, term_count, &expected) == NVFZF_OK,
        "%s baseline positions", label);
  size_t allocations = atomic_load(&matcher_alloc_calls);
  CHECK(allocations > 0 && expected.matched && expected.count > 0, "%s allocates positions", label);
  nvfzf_engine_free(engine);
  size_t errors = 0, fallbacks = 0;
  for (size_t failure = 1; failure <= allocations; failure++) {
    reset_matcher_allocations(0);
    engine = nvfzf_engine_create(); CHECK(engine, "%s fresh engine", label);
    reset_matcher_allocations(failure);
    NVFZFPositions actual = {(void *)1, 42, true};
    NVFZFStatus status = positions_oom_case(engine, input, query, terms, term_count, &actual);
    if (status == NVFZF_OK) {
      compare_positions(&actual, &expected, label); fallbacks++;
    } else {
      CHECK(status == NVFZF_OUT_OF_MEMORY, "%s allocation %zu status %d", label, failure, status);
      CHECK(!actual.offsets && !actual.count && !actual.matched, "%s OOM never exposes partial positions", label); errors++;
    }
    nvfzf_positions_free(&actual);
    reset_matcher_allocations(0);
    CHECK(positions_oom_case(engine, input, query, terms, term_count, &actual) == NVFZF_OK,
          "%s positions recover after allocation %zu", label, failure);
    compare_positions(&actual, &expected, label);
    nvfzf_positions_free(&actual); nvfzf_engine_free(engine);
  }
  CHECK(errors > 0, "%s must reach fatal position allocations", label);
  printf("Upstream position OOM %-18s: %zu ordinals, %zu errors, %zu complete fallbacks.\n",
         label, allocations, errors, fallbacks);
  nvfzf_positions_free(&expected);
}

static void test_matcher_allocations(void) {
  reset_allocations(0, 0, NULL);
  record_matcher_sites = true;
  reset_matcher_allocations(0);
  NVFZFEngine *engine = nvfzf_engine_create(); CHECK(engine, "upstream slab baseline");
  size_t slab_allocations = atomic_load(&matcher_alloc_calls);
  CHECK(slab_allocations == 3, "default slab has descriptor and two scratch allocations");
  nvfzf_engine_free(engine);
  for (size_t failure = 1; failure <= slab_allocations; failure++) {
    reset_matcher_allocations(failure);
    CHECK(!nvfzf_engine_create(), "slab allocation %zu returns no engine", failure);
  }
  reset_matcher_allocations(0);

  NVFZFCandidate parser_items[] = {{"alpha café", 11}, {"βeta café", 11}, {"absent", 6}};
  sweep_matcher_search("native parser", parser_items, 3, "'alpha | 'βeta café !absent", NULL, 0);
  sweep_matcher_positions("native parser", parser_items[0], "'alpha | 'βeta café !absent", NULL, 0);

  const size_t ascii_size = 40000, unicode_size = 20004, greedy_size = 140004;
  char *ascii = malloc(ascii_size), *unicode = malloc(unicode_size), *greedy = malloc(greedy_size);
  CHECK(ascii && unicode && greedy, "OOM fixture source allocation");
  memset(ascii, 'x', ascii_size); ascii[0] = 'a'; ascii[ascii_size - 1] = 'b';
  memset(unicode, 'x', unicode_size); memcpy(unicode, "é", 2); unicode[unicode_size - 1] = 'b';
  memset(greedy, 'x', greedy_size); memcpy(greedy, "é", 2); greedy[greedy_size - 1] = 'b';
  NVFZFTerm ab = {"ab", 2, NVFZF_TERM_FUZZY}, eb = {"éb", 3, NVFZF_TERM_FUZZY};
  NVFZFCandidate ascii_items[] = {{"ab", 2}, {ascii, ascii_size}};
  NVFZFCandidate unicode_items[] = {{"éb", 3}, {unicode, unicode_size}};
  NVFZFCandidate greedy_items[] = {{"éb", 3}, {greedy, greedy_size}};
  sweep_matcher_search("ASCII DP scratch", ascii_items, 2, NULL, &ab, 1);
  sweep_matcher_search("UTF8 retained map", unicode_items, 2, NULL, &eb, 1);
  sweep_matcher_search("UTF8 greedy map", greedy_items, 2, NULL, &eb, 1);
  sweep_matcher_positions("ASCII DP scratch", ascii_items[1], NULL, &ab, 1);
  sweep_matcher_positions("UTF8 retained map", unicode_items[1], NULL, &eb, 1);
  sweep_matcher_positions("UTF8 greedy map", greedy_items[1], NULL, &eb, 1);

  /* Earlier step already has a match. A scorer OOM in a later step must latch
     a terminal failure instead of completing a smaller list. */
  reset_matcher_allocations(0);
  engine = nvfzf_engine_create(); CHECK(engine, "partial scoring engine");
  NVFZFJob *job = NULL; bool finished = false;
  CHECK(nvfzf_job_create_terms(ascii_items, 2, &ab, 1, NULL, &job) == NVFZF_OK, "partial scoring job");
  CHECK(nvfzf_job_step(engine, job, 1, &finished) == NVFZF_OK && !finished, "first step matched");
  reset_matcher_allocations(1);
  CHECK(nvfzf_job_step(engine, job, 1, &finished) == NVFZF_OUT_OF_MEMORY && !finished,
        "later scorer OOM is terminal");
  reset_matcher_allocations(0);
  CHECK(nvfzf_job_step(engine, job, 1, &finished) == NVFZF_OUT_OF_MEMORY,
        "failed job cannot resume after OOM flag clears");
  NVFZFSearchResult partial = {(void *)1, 42};
  CHECK(nvfzf_job_finish(job, &partial) == NVFZF_OUT_OF_MEMORY && !partial.matches && !partial.count,
        "finalization cannot publish earlier matches after OOM");
  nvfzf_job_free(job); nvfzf_engine_free(engine);
  free(ascii); free(unicode); free(greedy);

  for (size_t i = 0; i < matcher_site_count; i++) {
    CHECK(matcher_sites[i].failed, "encountered upstream site %s:%d must receive failure injection",
          matcher_sites[i].file, matcher_sites[i].line);
    const char *file = strrchr(matcher_sites[i].file, '/');
    printf("  injected upstream allocation: %s:%d\n", file ? file + 1 : matcher_sites[i].file, matcher_sites[i].line);
  }
  printf("Upstream OOM coverage: %zu distinct parser/scorer/position/slab sites; all encountered sites injected.\n",
         matcher_site_count);
  record_matcher_sites = false;
  reset_matcher_allocations(0);
}
