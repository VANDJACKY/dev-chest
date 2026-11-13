# Python SQLAlchemy 完整使用实战文档

## 1. 文档简介

本文档面向Python开发者，详细讲解**SQLAlchemy 2.x** 版本全套使用教程，包含环境依赖安装、MySQL数据库连接配置、实体Model创建、字段注解、基础CURD操作、原生SQL执行、实体进阶操作等内容。文档所有示例均可直接复制运行，适用于本地开发、项目实战、后端接口开发等场景。

SQLAlchemy 是Python生态中最主流的ORM（对象关系映射）框架，支持多种关系型数据库（MySQL、PostgreSQL、SQLite、Oracle），开发者可通过面向对象的方式操作数据库，无需编写冗余SQL语句，同时兼容原生SQL，兼顾开发效率与灵活性。

## 2. 环境依赖

### 2.1 版本说明

- Python：>=3.8

- SQLAlchemy：2.x 最新稳定版

- 数据库：MySQL 5.7 / 8.0

- 连接器：pymysql（纯Python连接器，无额外依赖）

### 2.2 依赖包安装

需要同时安装SQLAlchemy核心库与MySQL连接器，执行以下pip安装命令：

```bash
# 安装SQLAlchemy核心框架
pip install sqlalchemy

# 安装mysql连接器 pymysql
pip install pymysql

# 国内镜像加速（可选，推荐）
pip install sqlalchemy pymysql -i https://pypi.tuna.tsinghua.edu.cn/simple
```

## 3. 数据库连接配置

### 3.1 连接参数说明

SQLAlchemy通过`create_engine`创建数据库引擎，核心连接URL格式如下：

```plain
mysql+pymysql://用户名:密码@IP地址:端口/数据库名?参数配置
```

参数详解：

- `mysql+pymysql`：指定数据库类型+连接器

- 用户名/密码：MySQL登录账号密码

- IP:端口：数据库地址，默认端口3306

- 数据库名：提前创建好的空数据库（SQLAlchemy不会自动创建数据库）

### 3.2 基础连接示例

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# 1. 初始化数据库引擎
# pool_recycle：重置超时连接，解决MySQL8小时断开连接问题
# echo=True：开启SQL日志打印，开发环境开启，生产环境关闭
engine = create_engine(
    url="mysql+pymysql://root:123456@127.0.0.1:3306/sql_demo",
    pool_recycle=3600,
    echo=True,
    autocommit=False,
    autoflush=False
)

# 2. 创建会话工厂，所有数据库操作都通过Session执行
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 3. 获取数据库会话
db = SessionLocal()
```

### 3.3 通用获取会话工具类（项目推荐）

封装通用会话获取函数，适配FastAPI/Flask等项目：

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from typing import Generator

# 数据库配置项
MYSQL_USER = "root"
MYSQL_PWD = "123456"
MYSQL_HOST = "127.0.0.1"
MYSQL_PORT = 3306
MYSQL_DB = "sql_demo"

# 初始化引擎
engine = create_engine(
    f"mysql+pymysql://{MYSQL_USER}:{MYSQL_PWD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}",
    pool_pre_ping=True,  # 自动检测连接有效性
    pool_recycle=3600,
    echo=False
)

SessionFactory = sessionmaker(bind=engine)

# 依赖注入获取会话
def get_db() -> Generator:
    db = SessionFactory()
    try:
        yield db
    finally:
        db.close()
```

## 4. 实体Model注解与创建

### 4.1 基础父类定义

所有自定义实体类必须继承SQLAlchemy提供的`DeclarativeBase`基类（2.x版本专用）：

```python
from sqlalchemy.orm import DeclarativeBase

# 定义实体基类，所有数据表实体继承此类
class Base(DeclarativeBase):
    pass
```

### 4.2 字段注解与数据类型

SQLAlchemy通过`Mapped`+字段类型做类型注解，替代旧版本Column写法，支持静态类型检测，常用字段类型如下：

|注解类型|对应MySQL类型|使用场景|
|---|---|---|
|Integer|int|主键、普通数字|
|String(n)|varchar(n)|字符串、账号、名称|
|Text|text|长文本、备注|
|Float|float|小数、金额|
|DateTime|datetime|时间日期|
|Boolean|tinyint(1)|布尔状态|

### 4.3 自定义实体Model完整示例

```python
from datetime import datetime
from sqlalchemy import Integer, String, DateTime, Boolean
from sqlalchemy.orm import Mapped, mapped_column
from base import Base  # 导入上方定义的Base基类

# 自定义用户实体类，对应数据库user数据表
class User(Base):
    # 指定数据表名称
    __tablename__ = "user"

    # 主键ID，自增、非空、唯一
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True, comment="用户主键ID")
    # 用户名，唯一、非空，长度32
    username: Mapped[str] = mapped_column(String(32), unique=True, nullable=False, comment="用户名")
    # 密码，非空
    password: Mapped[str] = mapped_column(String(64), nullable=False, comment="登录密码")
    # 手机号，允许为空
    phone: Mapped[str | None] = mapped_column(String(11), nullable=True, comment="手机号码")
    # 账号状态，默认正常（True）
    status: Mapped[bool] = mapped_column(Boolean, default=True, comment="账号状态：1正常 0禁用")
    # 创建时间，默认当前时间
    create_time: Mapped[datetime] = mapped_column(DateTime, default=datetime.now, comment="创建时间")
    # 更新时间，数据更新时自动刷新
    update_time: Mapped[datetime] = mapped_column(DateTime, default=datetime.now, onupdate=datetime.now, comment="更新时间")

    # 重写打印方法，方便调试
    def __repr__(self):
        return f"<User(id={self.id}, username={self.username}, phone={self.phone})>"
```

### 4.4 创建/删除数据表

```python
from base import Base
from engine import engine
from model.user import User

# 根据实体类自动创建所有数据表（仅创建不存在的表）
Base.metadata.create_all(bind=engine)

# 删除所有数据表（谨慎使用，生产环境禁止）
# Base.metadata.drop_all(bind=engine)
```

## 5. 实体Model基础CURD操作

所有操作基于上方定义的`User`实体类与数据库会话`db`，以下为完整增删改查示例。

### 5.1 新增数据（Create）

#### 5.1.1 单条数据新增

```python
from model.user import User

# 1. 初始化实体对象
user = User(
    username="zhangsan",
    password="123456",
    phone="13800138000"
)

# 2. 添加到会话
db.add(user)
# 3. 提交事务到数据库
db.commit()
# 4. 刷新实体，获取数据库自增主键ID
db.refresh(user)
print(f"新增用户ID：{user.id}")
```

#### 5.1.2 批量新增数据

```python
# 批量创建实体对象
user_list = [
    User(username="lisi", password="123456", phone="13800138001"),
    User(username="wangwu", password="123456", phone="13800138002")
]

# 批量添加
db.add_all(user_list)
db.commit()
```

### 5.2 查询数据（Read）

#### 5.2.1 查询所有数据

```python
# 查询user表所有数据
all_users = db.query(User).all()
for user in all_users:
    print(user.id, user.username, user.phone)
```

#### 5.2.2 根据主键查询

```python
# 根据ID查询单条数据，无数据返回None
user = db.query(User).get(1)
if user:
    print(user.username)
```

#### 5.2.3 条件查询

```python
# 等值条件查询
user = db.query(User).filter(User.username == "zhangsan").first()

# 多条件查询
user = db.query(User).filter(User.username == "zhangsan", User.status == True).first()

# 模糊查询
user_list = db.query(User).filter(User.username.like("%zhang%")).all()

# 范围查询
user_list = db.query(User).filter(User.id.between(1, 5)).all()
```

#### 5.2.4 分页与排序

```python
# 排序：id倒序
user_list = db.query(User).order_by(User.id.desc()).all()

# 分页：page=1，每页2条数据
page_num = 1
page_size = 2
user_page = db.query(User).offset((page_num-1)*page_size).limit(page_size).all()

# 获取数据总条数
total = db.query(User).count()
```

### 5.3 更新数据（Update）

#### 5.3.1 单条数据更新

```python
# 1. 查询需要更新的数据
user = db.query(User).get(1)
if user:
    # 2. 直接修改实体属性
    user.phone = "13900139000"
    user.password = "654321"
    # 3. 提交事务
    db.commit()
```

#### 5.3.2 批量条件更新

```python
# 将所有状态为False的账号，批量修改手机号
db.query(User).filter(User.status == False).update({User.phone: None})
db.commit()
```

### 5.4 删除数据（Delete）

#### 5.4.1 单条数据删除

```python
user = db.query(User).get(3)
if user:
    db.delete(user)
    db.commit()
```

#### 5.4.2 批量条件删除

```python
# 删除用户名为wangwu的数据
db.query(User).filter(User.username == "wangwu").delete()
db.commit()
```

## 6. 自定义原生SQL使用

针对复杂联表查询、聚合查询等ORM难以实现的场景，SQLAlchemy支持直接执行原生SQL语句。

### 6.1 执行查询类SQL

```python
# 编写原生查询SQL
sql = "SELECT id, username, phone FROM user WHERE status = :status"
# 执行SQL并绑定参数
result = db.execute(sql, {"status": True})
# 获取查询结果（字典格式）
rows = result.mappings().all()
for row in rows:
    print(row.id, row.username)
```

### 6.2 执行增删改原生SQL

```python
# 新增SQL
insert_sql = "INSERT INTO user(username, password) VALUES(:name, :pwd)"
db.execute(insert_sql, {"name": "zhaoliu", "pwd": "123456"})
db.commit()

# 更新SQL
update_sql = "UPDATE user SET phone = :phone WHERE id = :id"
db.execute(update_sql, {"phone": "13700137000", "id": 2})
db.commit()

# 删除SQL
delete_sql = "DELETE FROM user WHERE username = :name"
db.execute(delete_sql, {"name": "zhaoliu"})
db.commit()
```

### 6.3 无会话直接执行SQL

```python
from engine import engine

# 通过引擎直接执行SQL
with engine.connect() as conn:
    res = conn.execute(text("SELECT * FROM user"))
    print(res.all())
    conn.commit()
```

## 7. 高级拓展操作

### 7.1 事务回滚

数据库操作异常时，回滚事务，保证数据一致性：

```python
try:
    user1 = User(username="test1", password="123456")
    user2 = User(username="test1", password="123456") # 用户名重复，触发异常
    db.add_all([user1, user2])
    db.commit()
except Exception as e:
    # 异常回滚
    db.rollback()
    print(f"操作失败：{str(e)}")
```

### 7.2 字段筛选查询

查询指定字段，而非返回完整实体：

```python
# 仅查询用户名、手机号
res = db.query(User.username, User.phone).filter(User.status == True).all()
for username, phone in res:
    print(username, phone)
```

## 8. 常见问题与解决方案

### 8.1 8小时连接断开问题

MySQL默认闲置8小时自动断开连接，解决方案：创建引擎时添加 `pool_recycle=3600`，每小时重置连接。

### 8.2 中文乱码问题

连接URL追加编码参数，指定utf8mb4（支持emoji表情）：

```plain
mysql+pymysql://root:123456@127.0.0.1:3306/sql_demo?charset=utf8mb4
```

### 8.3 事务自动提交

开发阶段禁止开启自动提交，生产环境如需简化操作，可设置 `autocommit=True`，无需手动commit。

## 9. 项目目录结构（推荐）

```plain
sqlalchemy-demo/
├── config/          # 配置文件
│   └── settings.py  # 数据库账号密码配置
├── core/
│   ├── base.py      # 实体基类Base
│   └── engine.py    # 数据库引擎、会话
├── model/           # 所有数据实体Model
│   ├── __init__.py
│   └── user.py      # User实体类
└── main.py          # 测试入口
```

> （注：文档部分内容可能由 AI 生成）
