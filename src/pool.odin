package main

Pool_Key :: struct($Type: typeid)
{
  slot: u32,
  age:  u32,
}

Pool :: struct($Type: typeid, $N: int)
{
  things: [N]Type,
  count:  int,
  free:   [dynamic; N]Pool_Key(Type),
}

make_pool :: proc($Type: typeid, $N: int) -> (pool: Pool(Type, N))
{
  // The first slot will always mean an invalid key
  pool.count = 1
}

// TODO: Figure out how the iterators work in this language
pool_slice :: proc(pool: Pool($Type, $N)) -> (slice: []Type)
{
  return pool.things[:count]
}

pool_alloc :: proc(pool: ^Pool($Type, $N)) -> (key: Pool_Key(Type))
{
  if len(pool.free) > 0
  {
    key = pop_front(pool.free)

    // TODO: Some quick way to check that this slot is indeed unused...
    // could go back to internal linked list but want something that doesn't require modification
    // to the thing type... though maybe where statement can ensure struct members?
  }
  else
  {
    if pool.count < len(pool.things)
    {
      key.slot = pool.count
      key.age  = 0

      pool.count += 1
    }
    else
    {
      log.errorf("Attempted to allocate from pool while pool is full.")
    }
  }

  return key
}
