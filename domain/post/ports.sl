pub gc struct PostRepository {
    _pad: int
}

pub fn new_post_repository() -> PostRepository {
    return PostRepository { _pad: 0 };
}
