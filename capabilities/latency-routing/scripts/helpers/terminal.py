def get_link(title: str, url: str):
    return "\033]8;;{}\033\\{}\033]8;;\033\\".format(url, title)
