class Disk(object):
    def __init__(self) -> None:
        self.space = [None for i in range(10)]
        self.cur_used = 0
        pass

    def alloc_page(self):
        page = Page(self.cur_used)
        self.space[self.cur_used] = page
        self.cur_used += 1
        return page

class Page(object):
    def __init__(self, page_id) -> None:
        self.right_link = None
        self.page_id = page_id
        self.data = []
        self.cap = 3
        self.data_len = 0
        self.left_child = None
        self.right_child = None
        pass

    def set_right_link(self, page_id):
        self.right_link = page_id
    
    def set_left_child(self, child_page_id):
        self.left_child = child_page_id

    def set_right_child(self, child_page_id):
        self.right_child = child_page_id
    
    def insert(self, key, data) -> bool:
        if self.data_len + 1 == self.cap:
            return False
        else:
            self.data.append([key, data])
            self.data_len += 1
            return True
    

class BTree(object):
    def __init__(self, disk) -> None:
        self.root = None
        self.disk = disk
        pass

    def search(self, key):
        pass
    
    def insert(self, key, data):
        if not self.root:
            self.root = self.disk.alloc_page()
            self.root.insert(key, data)
        else:
            pass
    

if __name__ == '__main__':
    disk = Disk()
    btree = BTree(disk)
    btree.insert(1, 'a')
    btree.insert(2, 'b')
    btree.insert(3, 'b')
