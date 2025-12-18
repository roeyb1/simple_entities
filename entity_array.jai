Entity_Array :: struct (type: Type, items_per_bucket: int) {
    count: s64;

    allocator: Allocator;

    My_Bucket :: Entity_Bucket(type, items_per_bucket);  // Type alias; types are first-class.

    all_buckets:    [..] *My_Bucket;
    unfull_buckets: [..] *My_Bucket;
}

Entity_Bucket :: struct (type: Type, items_per_bucket: int) {
    occupied: [items_per_bucket] bool;  // Could make this an array of u64 and use one bit for each dude.
    data:     [items_per_bucket] type = ---;

    lowest_maybe_not_occupied: s32; // Index that _may_ not be occupied, to decrease search space when adding elements.
    bucket_index: u32;

    count := 0;
}

Entity_Locator :: struct {
    bucket_index: u32;
    slot_index:   s32;  // Signed because we do a trick where we set it to -1.
}


entity_array_reset :: (using array: *Entity_Array) {
    for all_buckets free(it,, allocator);
    array_reset(*all_buckets);
    array_reset(*unfull_buckets);

    count = 0;
}

entity_array_add :: (using array: *Entity_Array, item: array.type) -> (Entity_Locator, pointer: *array.type) {
    pointer, locator := find_and_occupy_empty_slot(array, initialize=false);
    pointer.* = item;

    return locator, pointer;
}

entity_array_find :: (using array: *Entity_Array, locator: Entity_Locator) -> array.type {
    bucket := all_buckets[locator.bucket_index];
    assert(bucket.occupied[locator.slot_index] == true);
    result := bucket.data[locator.slot_index];
    return result;
}

entity_array_find_pointer :: (using array: *Entity_Array, locator: Entity_Locator) -> *array.type {
    bucket := all_buckets[locator.bucket_index];
    assert(bucket.occupied[locator.slot_index] == true);
    result := *bucket.data[locator.slot_index];
    return result;
}

entity_array_remove :: (using array: *Entity_Array, locator: Entity_Locator) {
    bucket := all_buckets[locator.bucket_index];
    assert(bucket.occupied[locator.slot_index] == true);

    was_full := (bucket.count == bucket.items_per_bucket);
    
    bucket.occupied[locator.slot_index] = false;

    if locator.slot_index < bucket.lowest_maybe_not_occupied {
        bucket.lowest_maybe_not_occupied = cast(s32) locator.slot_index;
    }
    
    bucket.count -= 1;
    array.count  -= 1;

    if was_full {
        assert(array_find(array.unfull_buckets, bucket) == false);
        array_add(*array.unfull_buckets, bucket);
    }
}

find_and_occupy_empty_slot :: (using array: *Entity_Array, $initialize := true) -> *array.type, Entity_Locator {
    if !unfull_buckets.count  add_bucket(array);
    assert(unfull_buckets.count > 0);  // @Incomplete: Some kind of error handling!    

    bucket := unfull_buckets[0];

    index := -1;
    for bucket.lowest_maybe_not_occupied..bucket.items_per_bucket-1 {
        if !bucket.occupied[it] {       // @Speed: We can record the first non-empty index in the occupied list?
            index = it;
            break;
        }
    }

    assert(index != -1);

    bucket.occupied[index] = true;
    bucket.count += 1;
    bucket.lowest_maybe_not_occupied = cast(s32)(index+1);
    assert(bucket.count <= bucket.items_per_bucket);

    memory := *bucket.data[index];
    #if initialize {
        ini :: initializer_of(bucket.type);
        #if ini ini(memory);
        else memset(memory, 0, size_of(bucket.type));
    }
    
    array.count  += 1;

    if bucket.count == bucket.items_per_bucket {
        removed := array_unordered_remove_by_value(*array.unfull_buckets, bucket);
        assert(removed == 1);
    }

    locator: Entity_Locator;
    locator.bucket_index  = bucket.bucket_index;
    locator.slot_index    = cast(s32) index;
    
    return memory, locator;
}

entity_array_is_entry :: (using array: Entity_Array, locator: Entity_Locator) -> bool {
    if locator.bucket_index >= all_buckets.count return false;

    bucket := all_buckets[locator.bucket_index];

    if locator.slot_index >= bucket.count then return false;

    return bucket.occupied[locator.slot_index];
}



for_expansion :: (array: *$T/Entity_Array, body: Code, flags: For_Flags) #expand {
    `it_index: Entity_Locator;

    REVERSE :: cast(bool) (flags & .REVERSE);

    DO_POINTER :: true;

    for <=REVERSE bucket, bi: array.all_buckets {
        for <=REVERSE *=DO_POINTER  `it, i: bucket.data {
            if !bucket.occupied[i] continue;

            it_index.bucket_index = cast(u32) bi;
            it_index.slot_index = cast(s32) i;

            #insert (break=break bucket, remove={ assert(false); }) body;
        }
    }
}

operator *[] :: (using array: Entity_Array, index: int) -> *array.type {
    bucket_index := index / items_per_bucket;
    slot_index := index % items_per_bucket;
    bucket := all_buckets[bucket_index];
    assert(bucket.occupied[slot_index] == true);
    result := *bucket.data[slot_index];
    return result;
}

#scope_file

#import "Basic";  // For assert, array_*, New.


add_bucket :: (using array: *Entity_Array) -> *array.My_Bucket {
    assert(unfull_buckets.count == 0);

    if !all_buckets.count {  // Therefore this is the first call.
        if allocator.proc {
            all_buckets.allocator    = allocator;
            unfull_buckets.allocator = allocator;
        }
    }

    // We don't need to push a new context because we changed the allocators on the arrays manually,
    // and we are passing allocator arguments explicitly to New.

    new_bucket := New(My_Bucket,, allocator);
    new_bucket.bucket_index = cast(u32) all_buckets.count;
    assert(new_bucket.bucket_index == all_buckets.count);  // Will assert if we overflowed.

    array_add(*all_buckets,    new_bucket);
    array_add(*unfull_buckets, new_bucket);

    return new_bucket;
}

